# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..6\n"; }
END {print "not ok 1\n" unless $loaded;}
use Unicode::Map;
$loaded = 1;
print "ok 1\n";
print STDERR "\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

use strict;

#
# Don't care about warnings for this test.
#
$^W = 0;

my @test = ( 
   map { ref($_) ? $_ : [$_] }
   ["new_no_id",            "new: joker charset id"],
   ["new_id_select",        "new: preselected charset id"],
   ["new_id_select_compat", "new: preselected charset id, Map8 compatible"],
   ["cp936",                "map: eastern asia (takes a while)"],
   ["reverse",              "reverse unicode"],
);

{
   my $max = 0;
   my $len;
   for (0..$#test) { 
      $len = length($test[$_]->[$#{$test[$_]}]);
      $max = $len if $len>$max;
   }
      
   my ($name, $desc);
   my $i=2;
   for (sort {$test[$a]->[$#{$test[$a]}] cmp $test[$b]->[$#{$test[$b]}]} 
        0..$#test
   ) {
      ($name, $desc) = @{$test[$_]};
      $desc = $name if !defined $desc;
      _out($max, $i, $desc); 
      test ($i++, eval "&$name($_, \"$name\")");
   }
}

sub _out {
   my $max = shift;
   my $t = sprintf "Test %2d: %s ", @_;
   $t .= "." x (9 + 4 + $max - length($t));
   printf STDERR "$t ";
}

sub test {
   my ($number, $status) = @_;
   if ($status) {
      print STDERR "ok\n";
      print "ok $number\n";
   } else {
      print STDERR "failed!\n";
      print "not ok $number\n";
   }
}

#
# New
#

sub new_no_id {
   return 0 if !(my $Map = new Unicode::Map());
   my $_16bit = $Map->to_unicode("ISO-8859-1", "Käse");
   return 0 unless $_16bit eq "\0K\0ä\0s\0e";
1}

sub new_id_select {
   return 0 if !(my $Map = new Unicode::Map({ ID => "ISO-8859-1" }));
   my $_16bit = $Map->to_unicode("Käse");
   return 0 unless $_16bit eq "\0K\0ä\0s\0e";
1}

sub new_id_select_compat {
   return 0 if !(my $Map = new Unicode::Map("ISO-8859-1"));
   my $_16bit = $Map->to_unicode("Käse");
   return 0 unless $_16bit eq "\0K\0ä\0s\0e";
1}


#
# Eastern asia
#

sub cp936 {
   my $_unicode = 
      "\x8f\xd9\x66\x2f\x4e\x00\x4e\x2a\x4f\x8b\x5b\x50".
      "\xff\x0c\x8b\xf7\x6d\x4b\x8b\xd5\x30\x02\x00\x0d".
      "\00\x0d"
   ;
   my $_cp936 =
      "\xd5\xe2\xca\xc7\xd2\xbb\xb8\xf6\xc0\xfd\xd7\xd3".
      "\xa3\xac\xc7\xeb\xb2\xe2\xca\xd4\xa1\xa3\x0d\x0d"
   ;
   return 0 if !(my $Map = new Unicode::Map());
   return 0 if $_cp936   ne $Map->from_unicode("CP936", $_unicode);
   return 0 if $_unicode ne $Map->to_unicode  ("CP936", $_cp936);
   return 0 if $_cp936   eq $Map->from_unicode("CP936", $_cp936);
1}

sub reverse {
#
# 2do: constant treatment!
#
   return 0 if !(my $Map = new Unicode::Map());
   my $_16bit = "K\0ä\0s\0e\0";
   $Map->reverse_unicode($_16bit);
   return 0 unless $_16bit eq "\0K\0ä\0s\0e";
1}

