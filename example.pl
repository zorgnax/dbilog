#!/usr/bin/perl
# A small script to test using the module

use strict;
use warnings;
use lib "lib";
use DBI;
use DBI::Log trace => 1, timing => 1;

END {
    unlink "foo.db";
};

my $dbh = DBI->connect("dbi:SQLite:dbname=foo.db", "", "", {RaiseError => 1, PrintError => 0});

my $sth = $dbh->prepare("CREATE TABLE foo (a INT, b INT)");
$sth->execute();
$dbh->do("INSERT INTO foo VALUES (?, ?)", undef, 1, 2);
$dbh->selectcol_arrayref("SELECT * FROM foo");
eval {$dbh->do("INSERT INTO bar VALUES (?, ?)", undef, 1, 2)};

