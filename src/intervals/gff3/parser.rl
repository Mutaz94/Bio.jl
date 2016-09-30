#

%%{
    machine gff3parser;

    action finish_match {
        Ragel.@anchor!
        Ragel.@yield ftargs
    }

    action count_line { input.state.linenum += 1 }
    action anchor { Ragel.@anchor! }

    action directive {
        # TODO: Avoid allocation
        directive = Ragel.@ascii_from_anchor!
        if startswith(directive, "##gff-version")
            # ##gff-version 3.2.1
            input.version = VersionNumber(split(directive, r"\s+")[2])
        elseif startswith(directive, "##sequence-region")
            # ##sequence-region seqid start end
            vals = split(directive, r"\s+")
            push!(input.sequence_regions,
                Interval(vals[2], parse(Int, vals[3]), parse(Int, vals[4])))
        elseif startswith(directive, "##FASTA")
            input.fasta_seen = true
            input.state.finished = true
            if input.entry_seen
                Ragel.@yield ftargs
            else
                fbreak;
            end
        else
            # TODO: record other directives
        end
    }

    action implicit_fasta {
        input.fasta_seen = true
        input.state.finished = true
        if input.entry_seen
            p -= 2
            Ragel.@yield ftargs
        else
            p -= 1
            fbreak;
        end
    }

    # interval
    action seqname {
        input.entry_seen = true
        empty!(output.metadata.attributes)
        Ragel.@copy_from_anchor!(output.seqname)
        unescape_as_needed!(output.seqname)
    }
    action start   { output.first = Ragel.@int64_from_anchor! }
    action end     { output.last = Ragel.@int64_from_anchor! }
    action strand  { output.strand = convert(Strand, (Ragel.@char)) }

    # metadata
    action source     {
        Ragel.@copy_from_anchor!(output.metadata.source)
        unescape_as_needed!(output.metadata.source)
    }
    action kind       {
        Ragel.@copy_from_anchor!(output.metadata.kind)
        unescape_as_needed!(output.metadata.kind)
    }
    action score      { output.metadata.score = Nullable(Ragel.@float64_from_anchor!) }
    action nullscore  { output.metadata.score = Nullable{Float64}() }
    action phase      { output.metadata.phase = Nullable(Ragel.@int64_from_anchor!) }
    action nullphase  { output.metadata.phase = Nullable{Int}() }
    action attribute_key {
        Ragel.@copy_from_anchor!(input.key)
        unescape_as_needed!(input.key)
    }
    action attribute_value {
        pushindex!(output.metadata.attributes, input.key,
                   input.state.stream.buffer, upanchor!(input.state.stream), p)
    }

    newline        = '\r'? '\n' >count_line;
    hspace         = [ \t\v];
    blankline      = hspace* newline;
    # Just check that there's a digit. Actual validation happens when we parse
    # the float.
    floating_point = [ -~]* digit [ -~]*;

    comment   = '#' (any - newline - '#')* newline;
    directive = ("##" (any - newline)*) >anchor %directive newline;
    implicit_fasta = '>' >implicit_fasta;

    seqname    = [a-zA-Z0-9.:^*$@!+_?\-|%]* >anchor %seqname;
    source     = [ -~]* >anchor %source;
    kind       = [ -~]* >anchor %kind;
    start      = digit+ >anchor %start;
    end        = digit+ >anchor %end;
    score      = ((floating_point %score) | ('.' %nullscore)) >anchor;
    strand     = [+\-\.?] >strand;
    phase      = (([0-2] %phase) | ('.' %nullphase)) >anchor;

    attribute_char = [ -~] - [=;,];
    attribute_key = attribute_char* >anchor %attribute_key;
    attribute_value = attribute_char* >anchor %attribute_value;
    attribute = attribute_key '=' attribute_value (',' attribute_value)*;
    attributes = (attribute ';')* attribute?;

    non_entry = blankline | directive | comment | implicit_fasta;

    gff3_entry = seqname '\t' source '\t' kind '\t' start '\t' end '\t'
                 score   '\t' strand '\t' phase '\t' attributes
                 newline non_entry*;

    main := non_entry* (gff3_entry %finish_match)*;
}%%

%% write data;

Ragel.@generate_read!_function(
    "gff3parser",
    GFF3Reader,
    GFF3Interval,
    begin
        %% write exec;
    end)
