#!/usr/bin/perl
# A small script to test using the module

use strict;
use warnings;
use lib "lib";
use DBI;
use DBI::Log trace => 1, timing => 1;
use Data::Dumper;

END {
    unlink "foo.db";
};

my $dbh = DBI->connect("dbi:SQLite:dbname=foo.db", "", "", {RaiseError => 1, PrintError => 0});

my $sth = $dbh->prepare("CREATE TABLE foo (a INT, b INT)");
$sth->execute();
$dbh->do("INSERT INTO foo VALUES (?, ?)", undef, 1, 2);
$dbh->do("INSERT INTO foo VALUES (?, ?)", undef, 3, 4);
$dbh->do("INSERT INTO foo VALUES (?, ?)", undef, 5, 6);
$dbh->selectcol_arrayref("SELECT * FROM foo");
#eval {$dbh->do("INSERT INTO bar VALUES (?, ?)", undef, 1, 2)};

$sth = $dbh->prepare("SELECT * FROM foo WHERE a=?");
$sth->bind_param(1, 3);
$sth->execute();

while (my $row = $sth->fetchrow_hashref()) {
    print Dumper($row);
}

