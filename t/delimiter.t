use strict;
use warnings;
use lib "lib";
use Test::More;
use DBI;
use DBI::Log file => "foo2.sql", delimiter;

END {
    unlink "foo2.db";
    unlink "foo2.sql";
};

my $dbh = DBI->connect("dbi:SQLite:dbname=foo2.db", "", "", {RaiseError => 1, PrintError => 0});

my $sth = $dbh->prepare("CREATE TABLE foo2 (a INT, b INT)");
$sth->execute();
$dbh->do("INSERT INTO foo2 VALUES (?, ?)", undef, 1, 2);
$dbh->selectcol_arrayref("SELECT * FROM foo2");
eval {$dbh->do("INSERT INTO bar VALUES (?, ?)", undef, 1, 2)};

my $output = `cat foo2.sql`;
like $output, qr/^-- .*
-- execute .*
CREATE TABLE foo2 \(a INT, b INT\)

-- .*
-- do .*
INSERT INTO foo2 VALUES \('1', '2'\)

-- .*
-- selectcol_arrayref .*
SELECT \* FROM foo2

-- .*
-- do .*
INSERT INTO bar VALUES \('1', '2'\)
/, "log output";

done_testing();
