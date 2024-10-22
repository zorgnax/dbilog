#!/usr/bin/perl
use strict;
use warnings;
use lib "lib";
use Test::More;
use DBI;
use DBI::Log file => "foo.sql";

my $log_file = "foo.sql";
my $db_file = "foo.db";
my $json_file = "foo.json";

END {
    unlink $log_file;
    unlink $db_file;
    unlink $json_file;
};

my $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", "", "", {RaiseError => 1, PrintError => 0});

my $sth = $dbh->prepare("CREATE TABLE foo (a INT UNIQUE, b INT)");
$sth->execute();
check("prepare execute", qr{^-- .*
-- execute .*
CREATE TABLE foo \(a INT UNIQUE, b INT\)

});

$dbh->do("INSERT INTO foo VALUES (?, ?)", undef, 1, 2);
check("do", qr{^-- .*
-- do .*
INSERT INTO foo VALUES \('1', '2'\)

});

$dbh->selectcol_arrayref("SELECT * FROM foo");
check("selectcol_arrayref", qr{^-- .*
-- selectcol_arrayref .*
SELECT \* FROM foo

});

# gh#9 - ensure that we handle receiving statement handles and log them
# appropriately too
$sth = $dbh->prepare("SELECT * FROM foo");
$dbh->selectall_arrayref($sth, {Slice => {}});
check("selectall_arrayref", qr{^-- .*
-- selectall_arrayref .*
SELECT \* FROM foo

});

$sth = $dbh->prepare("INSERT INTO foo VALUES (?, ?)");
$sth->execute(2, 4);
check("placeholders on execute", qr{^-- .*
-- execute .*
INSERT INTO foo VALUES \('2', '4'\)
});

# make sure exceptions get logged (text output)
eval {$dbh->do("INSERT INTO bar VALUES (?, ?)", undef, 1, 2)};
like($@, qr/no such table: bar/, 'got expected do exception');
check("do exception still logs", qr{^-- .*
-- do .*
INSERT INTO bar VALUES \('1', '2'\)
});

$sth = $dbh->prepare("INSERT INTO foo VALUES (?, ?)");
eval { $sth->execute(1, 7) };
like($@, qr/UNIQUE constraint failed/, 'got expected execute exception');
check("execute exception still logs with placeholders", qr{^-- .*
-- execute .*
INSERT INTO foo VALUES \('1', '7'\)
});


# Manual re-import to change settings
DBI::Log->import(file => $json_file, format => "json");

my $query = "INSERT INTO foo VALUES (3, 4)";
$dbh->do($query);

my $output = `cat $json_file`;
like $output, qr/^\{"query": "INSERT INTO foo VALUES \(3, 4\)"/, "JSON format";

done_testing();

sub check {
    my ($desc, $regex) = @_;
    my $output = `cat $log_file`;
    like $output, $regex, $desc;
    truncate $log_file, 0;
}

