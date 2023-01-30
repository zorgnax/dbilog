package DBI::Log;

use 5.006;
no strict;
no warnings;
use DBI;
use Time::HiRes;

our $VERSION = "0.10";
our %opts = (
    file => $file,
    trace => 0,
    timing => 0,
    replace_placeholders => 1,
    fh => undef,
    exclude => undef,
    format => 'sql',
);

my $orig_execute = \&DBI::st::execute;
*DBI::st::execute = sub {
    my ($sth, @args) = @_;
    my $log = pre_query("execute", $sth->{Database}, $sth, $sth->{Statement}, \@args);
    my $retval = $orig_execute->($sth, @args);
    post_query($log);
    return $retval;
};

my $orig_selectall_arrayref = \&DBI::db::selectall_arrayref;
*DBI::db::selectall_arrayref = sub {
    my ($dbh, $query, $yup, @args) = @_;
    my $log = pre_query("selectall_arrayref", $dbh, undef, $query, \@args);
    my $retval = $orig_selectall_arrayref->($dbh, $query, $yup, @args);
    post_query($log);
    return $retval;
};

my $orig_selectcol_arrayref = \&DBI::db::selectcol_arrayref;
*DBI::db::selectcol_arrayref = sub {
    my ($dbh, $query, $yup, @args) = @_;
    my $log = pre_query("selectcol_arrayref", $dbh, undef, $query, \@args);
    my $retval = $orig_selectcol_arrayref->($dbh, $query, $yup, @args);
    post_query($log);
    return $retval;
};

my $orig_selectall_hashref = \&DBI::db::selectall_hashref;
*DBI::db::selectall_hashref = sub {
    my ($dbh, $query, $yup, @args) = @_;
    my $log = pre_query("selectall_hashref", $dbh, undef, $query, \@args);
    my $retval = $orig_selectall_hashref->($dbh, $query, $yup, @args);
    post_query($log);
    return $retval;
};

my $orig_selectrow_arrayref = \&DBI::db::selectrow_arrayref;
*DBI::db::selectrow_arrayref = sub {
    my ($dbh, $query, $yup, @args) = @_;
    my $log = pre_query("selectrow_arrayref", $dbh, $sth, $query, \@args);
    my $retval = $orig_selectrow_arrayref->($dbh, $query, $yup, @args);
    post_query($log);
    return $retval;
};

my $orig_selectrow_array = \&DBI::db::selectrow_array;
*DBI::db::selectrow_array = sub {
    my ($dbh, $query, $yup, @args) = @_;
    my $log = pre_query("selectrow_array", $dbh, undef, $query, \@args);
    my $retval = $orig_selectrow_array->($dbh, $query, $yup, @args);
    post_query($log);
    return $retval;
};

my $orig_selectrow_hashref = \&DBI::db::selectrow_hashref;
*DBI::db::selectrow_hashref = sub {
    my ($dbh, $query, $yup, @args) = @_;
    my $log = pre_query("selectrow_hashref", $dbh, undef, $query, \@args);
    my $retval = $orig_selectrow_hashref->($dbh, $query, $yup, @args);
    post_query($log);
    return $retval;
};

my $orig_do = \&DBI::db::do;
*DBI::db::do = sub {
    my ($dbh, $query, $yup, @args) = @_;
    my $log = pre_query("do", $dbh, undef, $query, \@args);
    my $retval = $orig_do->($dbh, $query, $yup, @args);
    post_query($log);
    return $retval;
};


sub import {
    my ($package, %args) = @_;
    for my $key (keys %args) {
        $opts{$key} = $args{$key};
    }
    if (!$opts{file}) {
        $opts{fh} = \*STDERR;
    }
    else {
        my $file2 = $opts{file};
        if ($file2 =~ m{^~/}) {
            my $home = $ENV{HOME} || (getpwuid($<))[7];
            $file2 =~ s{^~/}{$home/};
        }
        open $opts{fh}, ">>", $file2 or die "Can't open $opts{file}: $!";
    }

    # Load JSON, if we're asked for JSON output
    if ($opts{format} eq 'json') {
        eval "require JSON;"
            or die "Can't produce JSON output without JSON CPAN module!";
    } 
}

sub pre_query {
    my ($name, $dbh, $sth, $query, $args) = @_;
    my $log = {};
    my $mcount = 0;

    # Some DBI functions are composed of other DBI functions, so make sure we
    # are only logging the top level one. For example $dbh->do() will call
    # $dbh->execute() internally, so we need to make sure a DBI::Log function
    # logs the $dbh->do() and not the internal $dbh->execute(). If multiple
    # functions were called, we return and flag this log entry to be skipped in
    # the post_query() part.
    for (my $i = 0; my @caller = caller($i); $i++) {
        my ($package, $file, $line, $sub) = @caller;
        if ($package eq "DBI::Log") {
            $mcount++;
            if ($mcount > 1) {
                $log->{skip} = 1;
                return $log;
            }
        }
    }
    my @callers;
    for (my $i = 0; my @caller = caller($i); $i++) {
        push @callers, \@caller;
    }

    # Order the call stack based on the highest level calls first, then the
    # lower level calls. Once you reach a package that is excluded, do not show
    # any more lines in the stack trace. By default, it will exclude anything
    # past the DBI::Log package, but if user provides an exclude option, it will
    # stop there.
    my @filtered_callers;
    CALLER: for my $caller (reverse @callers) {
        my ($package, $file, $line, $sub) = @$caller;
        if ($package eq "DBI::Log") {
            last CALLER;
        }
        if ($opts{exclude}) {
            for my $item (@{$opts{exclude}}) {
                if ($package =~ /^$item(::|$)/) {
                    last CALLER;
                }
            }
        }
        push @filtered_callers, $caller;

    }
    if (!$opts{trace}) {
        @filtered_callers = ($filtered_callers[-1]);
    }

    my @stack;
    for my $caller (@filtered_callers) {
        my ($package, $file, $line, $sub) = @$caller;
        my $short_sub = $sub;
        $short_sub =~ s/.*:://;
        $short_sub = $name if $sub =~ /^DBI::Log::__ANON__/;
        push @stack, {
            sub => $short_sub,
            file => $file,
            line => $line,
        };
    }

    if (ref($query) && ref($query) eq "DBI::st") {
        $sth = $query;
        $query = $query->{Statement};
    }

    if ($dbh && $opts{replace_placeholders}) {
        # When you use $sth->bind_param(1, "value") the params can be found in
        # $sth->{ParamValues} and they override arguments sent in to
        # $sth->execute()

        my @args_copy = @$args;
        my %values;
        if ($sth && $sth->{ParamValues}) {
            %values = %{$sth->{ParamValues}};
        }
        for my $key (keys %values) {
            if (defined $key && $key =~ /^\d+$/) {
                $args_copy[$key - 1] = $values{$key};
            }
        }

        for my $i (0 .. @args_copy - 1) {
            my $value = $args_copy[$i];
            $value = $dbh->quote($value);
            $query =~ s{\?}{$value}e;
        }
    }

    $query =~ s/^\s*\n|\s*$//g;
    $log->{time_started} = Time::HiRes::time();
    if ($opts{format} eq 'sql') {
        $info = "-- " . scalar(localtime()) . "\n";
        my $stack_txt = join "", map { 
            "-- $_->{sub} $_->{file} $_->{line}\n" 
        } @stack;
        print {$opts{fh}} "$info$stack_txt$query\n";
    } else {
        # For JSON output we don't want to output anything yet,
        # so post_query() can emit the whole JSON object, just remember
        # them
        $log->{query} = $query;
        $log->{stack} = \@stack;
    }
    return $log;
}

sub post_query {
    my ($log) = @_;
    return if $log->{skip};
    if ($opts{timing}) {
        $log->{time_ended} = Time::HiRes::time();
        $log->{time_taken} = sprintf '%.3f', 
            $log->{time_ended} - $log->{time_started};
    }
   
    if ($opts{format} eq 'sql') {
        # For SQL output format, pre_query already printed most of
        # the info, we just need to add the time taken - and that only
        # if we're doing timings...
        if ($opts{timing}) {
            print {$opts{fh}} "-- $log->{time_taken}s\n";
        }
        print {$opts{fh}} "\n";
    } elsif ($opts{format} eq 'json') {
        # print all the info as JSON
        print {$opts{fh}} JSON::to_json($log) . "\n";
    }

}

1;

__END__

=encoding utf8

=head1 NAME

DBI::Log - Log all DBI queries

=head1 SYNOPSIS

    use DBI::Log;

=head1 DESCRIPTION

You can use this module to log all queries that are made with DBI. You just need
to include it in your script and it will work automatically. By default, it will
send output to STDERR, which is useful for command line scripts and for CGI
scripts since STDERR will appear in the error log.

If you want to log elsewhere, set the file option to a different location.

    use DBI::Log file => "~/querylog.sql";

Each query in the log is prepended with the date and the place in the code where
it was run from. You can add a full stack trace by setting the trace option.

    use DBI::Log trace => 1;

If you want timing information about how long the queries took to run add the
timing option.

    use DBI::Log timing => 1;

If you want to exclude function calls from within a certain package appearing in
the stack trace, you can use the exclude option like this:

    use DBI::Log exclude => ["DBIx::Class"];

It will exclude any package starting with that name, for example
DBIx::Class::ResultSet DBI::Log is excluded by default.

The log is formatted as SQL, so if you look at it in an editor, it might be
highlighted. This is what the output may look like:

    -- Fri Sep 11 17:31:18 2015
    -- execute t/test.t 18
    CREATE TABLE foo (a INT, b INT)

    -- Fri Sep 11 17:31:18 2015
    -- do t/test.t 21
    INSERT INTO foo VALUES ('1', '2')

    -- Fri Sep 11 17:31:18 2015
    -- selectcol_arrayref t/test.t 24
    SELECT * FROM foo

    -- Fri Sep 11 17:31:18 2015
    -- do t/test.t 27
    -- (eval) t/test.t 27
    INSERT INTO bar VALUES ('1', '2')

The default format, as illustrated above, is the SQL queries, with information
added as SQL comments - so you can have a .sql file you could pass to your
DB to re-run those queries, etc.

JSON output is also available, enable it by setting the C<format> option
to C<json> e.g.:

    use DBI::Log format => 'json';

Query logs will then be emitted in "line-delimited JSON" format, where each
"record" is a JSON object, separated by newlines - this format is understood
by many tools such as C<jq>, ElasticSearch's C<logstash> etc, and is useful
if you want to post-process the information - for example, using jq to
get only queries which took longer than a second:

    jq 'select(.time_taken >= 1)' < querylog.json

There is a built-in way to log with DBI, which can be enabled with
DBI->trace(1), but the output is not easy to read through.

This module integrates placeholder values into the query, so the log will
contain valid queries; placeholder values set by C<bind_param()> on a prepared
statement handle will take precedence over any passed to e.g. C<execute()>.

Replacement of placeholders with their values can be disabled with the
option `<replace_placeholders>`, e.g.:
 
    use DBI::Log replace_placeholders => 0;

This may be useful if you're doing later processing on the log, e.g. parsing
it and grouping by queries, and want all executions of the same query to
look alike without the values.

=head1 METACPAN

L<https://metacpan.org/pod/DBI::Log>

=head1 REPOSITORY

L<https://github.com/zorgnax/dbilog>

=head1 AUTHOR

Jacob Gelbman, E<lt>gelbman@gmail.comE<gt>

=head1 CONTRIBUTORS

=over

=item * Árpád Szász, E<lt>arpad.szasz@plenum.roE<gt>

=item * Pavel Serikov

=item * David Precious (BIGPRESH) - E<lt>davidp@preshweb.co.ukE<gt>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2015 by Jacob Gelbman

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself, either Perl version 5.18.2 or, at your option,
any later version of Perl 5 you may have available.

=cut

