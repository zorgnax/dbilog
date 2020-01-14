use strict;
use warnings;
use lib "lib";
use lib "t";
use Test::More;

END {
    unlink "foo.db";
    unlink "foo.sql";
};

require ABC;


my $output = `cat foo.sql`;
like $output, qr/^-- .*
-- execute .*
CREATE TABLE foo \(a INT, b INT\)

-- .*
-- do .*
INSERT INTO foo VALUES \('1', '2'\)

-- .*
-- selectcol_arrayref .*
SELECT \* FROM foo

-- .*
-- do .*
INSERT INTO bar VALUES \('1', '2'\)
/, "log output";

done_testing();
