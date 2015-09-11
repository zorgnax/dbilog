use strict;
use warnings;
use lib "lib";
use Test::More;
use DBI::Log;
$DBI::Log::path = "";
$DBI::Log::array = 1;

# last query
sub z () {return $DBI::Log::queries[-1]}

END {unlink "foo.db"};

my %params = (RaiseError => 1, PrintError => 0);
my $dbh = DBI->connect("dbi:SQLite:dbname=foo.db", "", "", \%params);

my $sth = $dbh->prepare("CREATE TABLE foo (a INT, b INT)");
$sth->execute();
ok z eq "CREATE TABLE foo (a INT, b INT)", "prepare-execute combo";

$dbh->do("INSERT INTO foo VALUES (?, ?)", undef, 1, 2);
ok z eq "INSERT INTO foo VALUES ('1', '2')", "do and fills ?";

$dbh->selectcol_arrayref("SELECT * FROM foo");
ok z eq "SELECT * FROM foo", "selectcol_arrayref";

eval {$dbh->do("INSERT INTO bar VALUES (?, ?)", undef, 1, 2)};
ok z eq "INSERT INTO bar VALUES ('1', '2')", "dying queries";

done_testing();

