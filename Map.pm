#
# $Id: Map.pm,v 1.79 1998/02/12 05:03:13 schwartz Exp $
#
# Unicode::Map
#
# Documentation at end of file.
#
# Copyright (C) 1998 Martin Schwartz. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Contact: schwartz@cs.tu-berlin.de
#

package Unicode::Map;
use strict;
use vars qw($VERSION @ISA $DEBUG);

$VERSION='0.104'; 

require DynaLoader; @ISA=qw(DynaLoader);
bootstrap Unicode::Map $VERSION;

sub NOISE   () { 1 }

sub MAGIC   () { 0xB827 } # magic word

sub M_END   () { 0 }      # end
                          
sub M_INF   () { 1 }      # infinite subsequent entries (default)
sub M_BYTE  () { 2 }      # 1..255 subsequent entries 
                 
sub M_VER   () { 4 }      # (Internal) file format revision.
            
sub M_AKV   () { 6 }      # key1, val1, key2, val2, ... (default)
sub M_AKAV  () { 7 }      # key1, key2, ..., val1, val2, ...
sub M_PKV   () { 8 }      # partial key value mappings
            
sub M_CKn   () { 10 }     # compress keys not
sub M_CK    () { 11 }     # compress keys (default)
            
sub M_CVn   () { 13 }     # compress values not
sub M_CV    () { 14 }     # compress values (default)

##
## The next entries are for info, only. They are stored as unicode strings.
##

sub I_NAME  () { 20 }     # Character Set Name
sub I_ALIAS () { 21 }     # Character Set alias name (several entries allowed)
sub I_VER   () { 22 }     # Mapfile revision
sub I_AUTH  () { 23 }	  # Mapfile authRess
sub I_INFO  () { 24 }     # Some userEss definable string

##
## --- Init ---------------------------------------------------------------
##

my $MAP_Pathname = 'Unicode/Map';
my @MAP_Path     = _get_standard_pathes();

my @order = (
   { 1=>"C", 2=>"n", 3=>"N", 4=>"N" },  # standard ("Network order")
   { 1=>"C", 2=>"v", 3=>"V", 4=>"V" },	# reverse  ("Vax order")
);

my %registry = ();
my %mappings = ();
my $registry_loaded = 0;

_init_registry();

##
## --- public conversion methods ------------------------------------------
##

sub to_8 { goto &from_unicode }

sub from_unicode {
   my $S = shift;
   $S -> _to ("TO_CUS", $S->_csid||shift, @_);
}

sub new {
#
# $ref||undef = Unicode::Map->new()
#
   my ($proto, $parH) = @_;
   my $S = bless ({}, ref($proto) || $proto);
   $S -> noise(NOISE);
   if ($parH) {
      if (ref($parH)) {
         $S -> Startup ($parH->{"STARTUP"})  if $parH->{"STARTUP"};
         if ($parH->{"ID"}) {
            return 0 if !($S->_csid ($S->id($parH->{"ID"})));
         }
      } else {
         # For Map8 compatibility...
         return 0 if ! ($S->_csid ($S->id($parH)));
      }
   }
   $S -> _load_registry();
   $S;
}

sub noise { shift->_member("P_NOISE", @_) }

# Unicode::Map.xs -> reverse_unicode 

sub to16 { goto &to_unicode }

sub to_unicode {
   my $S = shift;
   $S -> _to ("TO_UNI", $S->_csid||shift, @_);
}

## 
## --- public maintainance methods ----------------------------------------
##

sub alias { 
   @{$registry{$_[1]} -> {"ALIAS"}};
}

sub dest {
   my $tmp = shift->_dest(shift()); $tmp =~ s/^\///;
   $MAP_Pathname."/".$tmp;
}

sub id {
   shift->_real_id(shift());
}

sub ids { 
   (sort {$a cmp $b} grep {!/^GENERIC$/i} keys %registry);
}

sub info  { 
   $registry{$_[1]} -> {"INFO"};
}

sub read_text_mapping {
   my ($S, $csid, $textpath, $style) = @_;
   return 0 if !($csid = $S->id($csid));
   $S->_msg("reading") if $S->noise>0;
   $S->_read_text_mapping($csid, $textpath, $style);
}

sub src   { 
   $registry{$_[1]} -> {"SRC"};
}

sub style { 
   $registry{$_[1]} -> {"STYLE"};
}

sub write_binary_mapping {
   my ($S, $csid, $binpath) = @_;
   return 0 if !($csid = $S->id($csid)); 
   $binpath = $S->_get_path($S->_dest($csid)) if !$binpath; 
   return 0 if !$binpath;
   $S->_msg("writing") if $S->noise>0;
   $S->_write_IMap_to_binary($csid, $binpath);
}

##
## --- Application program interface --------------------------------------
##

sub Startup { shift->_member("STARTUP", @_) }

##
## --- private methods ----------------------------------------------------
##

sub _member    { my $S=shift; my $n=shift if @_; $S->{$n}=shift if @_; $S->{$n}}

sub _csid      { shift->_member("P_CSID", @_) }
sub _error     { my $S=shift; $S->Startup ? $S->Startup->error(@_) : 0 }
sub _msg       { my $S=shift; $S->Startup ? $S->Startup->msg(@_) : 0 }
sub _msg_fin   { my $S=shift; $S->Startup ? $S->Startup->msg_finish(@_) : 0 }
sub _IMap      { shift->_member("I", @_) }

sub _dest  { $registry{$_[1]} -> {"DEST"} }

sub _dump {
   my $S = shift;
   print "Dumping Mapping $S:\n";
   if ($S->Startup) {
      print "   - Startup object: ".$S->Startup."\n";
   } else {
      print "   - no Startup object\n";
   } 
   if (%registry) {
      print "   - Mapping: " . (keys %registry) . " entries defined.\n";
   } else {
      print "   - No mappings!\n";
   }
   if ($S->_IMap) {
      print "   - IMap:\n";
      my ($k,$v); while(($k,$v)=each %{$S->_IMap}) {
         printf "      %10s => %s\n", $k, $v;
      }
   }
   if (%mappings) {
      print "   - Mappings:\n";
      my ($k,$v); while(($k,$v)=each %mappings) {
         printf "      %10s => %s\n", $k, $v;
      }
   }
1}

sub _real_id {
   my ($S, $csid) = @_;
   if (!%registry) {
      return $S->_error("No mapping definitions!\n");
   }
   return $csid if defined $registry{$csid};
   my $id=""; 
   my (@tmp, $k, $v);
   while (($k,$v) = each %registry) {
      next if !$k || !$v;
      if ($csid =~ /^$k$/i) {
         $id=$k; last;
      } else {
         for (@{$v->{"ALIAS"}}) {
            if (/^$csid$/i) {
               $id=$k; last;
            }
         }
      }
   }
   while (($k, $v) = each %registry) {}
   return $S->_error("Character Set $csid not defined!") if !$id;
   $id;
}

sub _to {
#
# 1||0      = $S -> _to ("TO_UNI"||"TO_CUS", $csid, $src||$srcR, $destR, $o, $l)
# $text||"" = $S -> _to ("TO_UNI"||"TO_CUS", $csid, $src||$srcR, "",     $o, $l)
#
   my ($S, $to, $csid, $srcR, $destR, $o, $l) = @_;
   return 0 if !($csid = $S->_real_id($csid));
   return 0 if !$S->_load_TMap($csid);

   my ($cs1, $n1, $cs2, $n2, $tmp) = (0, 0, 0, 0, "");
   my (@M, @C);

   my $destbuf = ""; 
   my $srcbuf  = ref($srcR) ? $$srcR : $srcR;

   my $C = $mappings{$csid}->{$to};

   if ($S->noise>2) {
      $S->_msg("mapping ".(($to=~/^to_unicode$/i) ? "to Unicode" : "to $csid"));
   }
   my ($csa,$na,$csb,$nb);
   my @n = sort { 
      ($csa, $na) = split/,/,$a;
      ($csb, $nb) = split/,/,$b;
      $csa*$na <=> $csb*$nb
   } keys %$C;
   if (!$#n) {
      ($cs1, $n1, $cs2, $n2) = split /,/,$n[0];
      $destbuf = $S->_map_hash($srcbuf, 
         $C->{$n[0]}, 
         $n1*$cs1,
         $o||undef, $l||undef
      );
   } else {
      $destbuf = $S->_map_hashlist($srcbuf, 
         [map $C->{$_}, @n],
         [map {($cs1,$n1)=split/,/; int($cs1*$n1)} @n],
         $o, $l
      );
   }
   if ($destR) {
      $$destR=$destbuf; 1;
   } else {
      $destbuf;
   }
}

sub _init_registry {
   %registry = ();
   $registry_loaded = 0;
   _add_registry_entry("GENERIC", "GENERIC", "GENERIC");
1}

sub _unload_registry { 
   _init_registry;
}

##
## --- Binary to TMap -----------------------------------------------------
##

#  TMap structure:
#  
#  %T = (
#     $CSID => {
#        TO_CUS  => {
#           "$cs_a1,$n_a1,$cs_a2,$n_a2" => {
#              "str_a1_1" => "str_a2_1", ... , 
#              "str_a1_n" => "str_a2_n",
#           }, ... ,
#           "$cs_x1,$n_x1,$cs_x2,$n_x2" => {
#              "str_x1_1" => "str_x2_1", ... , 
#              "str_x1_n" => "str_x2_n",
#           }
#        }
#        TO_UNI => {
#           "$cs_a2,$n_a2,$cs_a1,$n_a1" => {
#              "str_a2_1" => "str_a1_1", ... ,
#              "str_a2_n" => "str_a1_n",
#           }, ... ,
#           "$csx2,$nx2,$csx1,$nx1" => {
#              "str_x2_1" => "str_x1_1", ... ,
#              "str_x2_n" => "str_x1_n",
#           }
#        }
#     }
#  );

sub _load_TMap {
   my ($S, $csid) = @_;
   return 1 if $mappings{$csid};
   return 0 if !$S->_read_binary_to_TMap($csid);
1}

sub _read_binary_to_TMap {
   my ($S, $csid) = @_;
   my %U = (); 
   my %C = ();
   my $buf = "";

   #
   # read file
   #
   return $S->_error ("Cannot find mapping file for id \"$csid\"!")
      if !(my $file = $S->_get_path($S->_dest($csid)))
   ;
   return $S->_error ("Cannot open binary mapping \"$file\"!") 
      if !open(MAP1, $file)
   ;
   my $size = read MAP1, $buf, -s $file;
   close MAP1;
   return $S->_error ("Error while reading mapping \"$file\"!")
      if ($size != -s $file)
   ;

   if ($size>0x1000) {
      $S->_msg("loading mapfile \"$csid\"") if $S->noise>0;
   } else {
      $S->_msg("loading mapfile \"$csid\"") if $S->noise>2;
   }

   return $S->_error ("Error in binary map file!\n")
      if !$S->_read_binary_mapping($buf, 0, \%U, \%C)
   ;

   if ($size>0x1000) {
      $S->_msg("loaded") if $S->noise>0;
   } else {
      $S->_msg("loaded") if $S->noise>2;
   }

   $mappings{$csid} = {
      TO_CUS  => \%C,
      TO_UNI => \%U
   };
   #$S->_dump_TMap ($mappings{$csid});
1}

sub _dump_TMap {
   my ($S, $TMap) = @_;
   print "\nDumping TMap $TMap\n";
   my ($pat1, $pat2, $up1, $up2);
   foreach (keys %$TMap) {
      my $subTMap = $TMap->{$_};
      print "SubTMap $_:\n";
      my @n = sort {(split/,/,$b)[0] <=> (split/,/,$a)[0]} keys %$subTMap;
      for (@n) {
         my ($cs1, $n1, $cs2, $n2) = split /,/;
         print "   Submapping $cs1 bytes ($n1 times) => "
            ."$cs2 bytes ($n2 times):\n"
         ;
         my $s="";
         $pat1 = ("%0".($cs1*2)."x ") x $n1;
         $pat2 = ("%0".($cs2*2)."x ") x $n2;
         $up1 = ($order[0]->{$cs1}).$n1;
         $up2 = ($order[0]->{$cs2}).$n2;
         my $subsubTMap = $subTMap->{$_};
         for (sort keys %$subsubTMap) {
           printf "      $pat1 => $pat2\n",
              unpack($up1, $_),
              unpack($up2, $subsubTMap->{$_})
           ;
         }
      }
   }
   print "Dumping done.\n\n";
}

##
## --- Text (Unicode, Keld) to IMap ---------------------------------------
##

sub _read_text_mapping {
   my ($S, $id, $path, $style) = @_;
   $S->_IMap({}) if !defined $S->_IMap;
   return $S->_error("Bad charset id") if (!$id || !$registry{$id});
   if ($style =~ /^keld$/i) {
      $S->_read_text_keld_to_IMap($id, $path);
   } elsif ($style =~ /^reverse$/i) {
      $S->_read_text_unicode_to_IMap($id, $path, 2, 1);
   } elsif (!$style || $style=~/^unicode$/i) {
      $S->_read_text_unicode_to_IMap($id, $path, 1, 2);
   } else {
      my ($vendor, $unicode) = ($style =~ /^\s*(\d+)\s+(\d+)/);
      if ($vendor && $unicode) {
         $S->_read_text_unicode_to_IMap($id, $path, $vendor, $unicode);
      } else {
         return $S->_error("Unknown style '$style'");
      }
   }
}

sub _read_text_keld_to_IMap {
   my ($S, $csid, $path) = @_;
   my %U = (); 
   my ($k, $v);
   my $com = ""; my $esc = "";
   return $S->_error("Cannot find text file!") if !$path;
   return $S->_error ("Cannot open text file \"$path\"!") 
      if !open(MAP2, $path)
   ;
   my $is_org=$/; $/="\n";
   while(<MAP2>) {
      s/$com.*// if $com;
      s/^\s+//; s/\s+$//; next if !$_; 
      last if /^CHARMAP/i;
      ($k, $v) = split /\s+/,$_,2;
      if ($k =~ /<comment_char>/i) { $com = $v; next }
      if ($k =~ /<escape_char>/i)  { $esc = $v; next }
   }
   my (@l, $f, $t);
   my $escx = $esc."x";
   while(<MAP2>) {
      s/$com.*// if $com;
      next if ! /$escx([^\s]+)\s+<U([^>]+)/;
      $U{length($1)*4}->{hex($1)} = hex($2);
   }
   $/=$is_org;
   close(MAP2);
   #$S->_dump_IMap(\%U);
   $S->_IMap->{$csid} = \%U;
1}

sub _read_text_unicode_to_IMap {
#
# Converts map files like created by Unicode Inc. to IMap
#
   no strict;
   my ($S, $csid, $file, $row_vendor, $row_unicode) = @_;
   my %U = (); 

   return $S->_error ("Cannot open text mapping \"$file\"!") 
      if !open(MAP3, $file)
   ;
   my (@l, $f, $t);
   my $hex = '(?:0x)?([^\s]+)\s+';
   my $hexgap = '(?:0x)?[^\s]+\s+';
   my ($min, $max) = ($row_vendor, $row_unicode);
   ($min, $max) = ($row_unicode, $row_vendor) if $row_unicode<$row_vendor;
   my $gap1 = $hexgap x ($min - 1);
   my $gap2 = $hexgap x ($max - $min - 1);
   if ($row_vendor > $row_unicode) {
      $row_unicode=1; $row_vendor=2;
   } else {
      $row_unicode=2; $row_vendor=1;
   }

   # Info fields in comments: (at this release still unused)
   my $Name = "";
   my $Unicode_version = "";
   my $Table_version = "";
   my $Date = "";
   my $Authresses = "";

   my $comment_info = 1; my $comment_authress=0;
   while(<MAP3>) {
      if ($comment_info && !/#/) {
         $comment_info = 0;
      }
      if ($comment_info) {
         if ($comment_authress && (/^#\s*$/ || /^#[^:]:/)) {
            $comment_authress = 0;
         }
         if (/#\s*name\S*:\s*(.*$)/i) {
            $Name = $1;
         }
         if (/#\s*unicode\s*version\S*:\s*(.*$)/i) {
            $Unicode_version = $1;
         }
         if (/#\s*table\s*version\S*:\s*(.*$)/i) {
            $Table_version = $1;
         }
         if (/#\s*date\S*:\s*(.*$)/i) {
            $Date = $1;
         }
         if ($comment_authress) {
            $Authresses .= ", $1" if /^#\s*(.+$)/;
         } elsif (/#\s*Author\S*:\s*(.*$)/i) {
            $Authresses = $1; $comment_authress=1;
         }
      }
      s/#.*$//; 
      next if !$_;
      next if ! /^$gap1$hex$gap2$hex/;
      ($f, $t) = ($$row_vendor, $$row_unicode);
      if (index($t, "+")<0) {
         $U{length($f)*4}->{hex($f)} = hex($t);
      } else {
         @l = map hex($_), split /\+/, $t;
         $U{(length($f)*4).",".($#l+1)}->{hex($f)} = [@l];
      }
   }
   close(MAP3);
   #$S->_dump_IMap(\%U);
   $S->_IMap->{$csid} = \%U;
1}

sub _dump_IMap {
#
# Dump IMap
#
   my ($S, $U) = @_;
   print "\nDumping IMap entry.\n";
   my ($U1, @list);
   for (keys %{$U}) {
      print "   From size = $_ bits:\n";
      my $size = $_ / 4;
      $U1 = $U->{$_};
      for (sort {$a <=> $b} keys %{$U1}) {
         printf (("      %0$size"."x => "), $_);
         if (ref($U1->{$_})) {
            @list = @{$U1->{$_}};
            printf "(".("%04x " x ($#list+1)).")\n", @list;
         } else {
            printf "%04x\n", $U1->{$_};
         }
      }
   }
1}

##
## --- IMap to binary -----------------------------------------------------
##

sub _write_IMap_to_binary {
   my ($S, $csid, $path) = @_;
   return $S->_error("Integer Map \"$csid\" not loaded!\n")
      if !(my $IMap = $S->_IMap->{$csid})
   ;
   return $S->_error("Cannot open output table \"$path\"!")
      if !open (MAP4, ">$path"); 
   ;
   my $str = "";
   $str .= _map_binary_begin();
   $str .= _map_binary_stream(I_NAME, $S->_to_unicode($csid));
   $str .= _map_binary_mode(M_BYTE);
   $str .= _map_binary_mode(M_PKV);
   my ($from, $to_n);
   for (keys %{$IMap}) {
      ($from, $to_n) = split /\s*,\s*/;
      $str .= $S->_map_binary_submapping($IMap->{$_}, $from, 16, $to_n||1);
   }
   $str .= _map_binary_mode(M_END);
   print MAP4 "$str";
   close (MAP4);
1}

sub _to_unicode {
   my ($S, $txt) = @_;
   $S -> to_unicode ($ENV{LC_CTYPE}, \$txt);
}

sub _map_binary_begin {
   pack($order[0]->{2}, MAGIC);
}

sub _map_binary_end {
   pack("C", M_END);
}

sub _map_binary_submapping {
   my ($S, $mapH, $size1, $size2, $n2) = @_;
   return $S->_error ("No IMap specified!") if !%$mapH;

   if ($n2*$size2>0xffff) {
      return $S->_error ("Bad n character mapping! Too many chars!");
   }

   my $bs1S = $order[0]->{int(($size1+7)/8)};
   my $bs2S = $order[0]->{int(($size2+7)/8)}.$n2;
   return $S->_error ("'From' characters have zero size!") if !$bs1S;

   my $str = "";
   $str .= pack("C4", ($size1, 1, $size2, $n2));
   
   my @key = sort {$a <=> $b} keys %$mapH;	# print "keys=(@key)\n";
   my @val = map $mapH->{$_}, @key;		# print "val=(@val)\n";
   my $max = $#key;

   my ($kkey, $kbegin, $kend, $kn, $vkey, $vbegin, $vend, $vn);
   if ($n2==1) {
      $kkey = _list_to_intervals(\@key, 0, $#key);
      while (@$kkey) {
         $kbegin = shift(@$kkey);
         $kend   = shift(@$kkey);
         #print "kbegin=$kbegin kend=$kend klen=".($kend-$kbegin+1)."\n";
         $str .= pack("C", $kend-$kbegin+1);
         $str .= pack($bs1S, $key[$kbegin]);
         $vkey = _list_to_intervals(\@val, $kbegin, $kend);
         while (@$vkey) {
            $vbegin = shift (@$vkey);
            $vend   = shift (@$vkey);
            $str .= pack("C", $vend-$vbegin+1);
            $str .= pack($bs2S, $val[$vbegin]);
         }
      }
   } else {
      $str .= _map_binary_mode(M_CVn);
      $kkey = _list_to_intervals(\@key, 0, $#key);
      while (@$kkey) {
         $kbegin = shift(@$kkey);
         $kend   = shift(@$kkey);
         $str .= pack("C", $kend-$kbegin+1);
         $str .= pack($bs1S, $key[$kbegin]);
         for ($kbegin..$kend) {
            $str .= pack($bs2S, @{$val[$_]});
         }
      }
   }
   $str .= _map_binary_mode(M_END);
   $str;
}

sub _map_binary_mode {
   my ($mode) = @_;
   return "\0".pack("C", $mode)."\0";
}

sub _map_binary_stream {
   my ($mode, $str) = @_;
   if (length($str) > 255) {
      $str = substr($str, 0, 255);
   }
   my $len = length($str);
   return "\0".pack("C2", $mode, $len).$str;
}

##
## --- registry file -------------------------------------------------------
##

#
# Registry structure:
#
# registry = (
#    $CSID => {
#       "ALIAS" => [alias1, alias2, ... , aliasn],
#       "DEST"  => "/ADOBE/ZDINGBAT.map",
#       "INFO"  => "Some info",
#       "SRC"   => "/home/hermine/Unicode/VENDORS/ADOBE/ZDINGBAT.TXT",
#       "STYLE" => "reverse",
#    }
# )
#

sub _load_registry {
   return 1 if $registry_loaded;
   my ($S) = @_;
   $S->_msg("loading unicode registry") if $S->noise>2;
   return 0 if !(my $path = $S->_get_path("REGISTRY"));
   my %var = ();
   my ($k, $v);
   return $S->_error("Cannot find registry file!") if !$path;

   return $S->_error ("Cannot open registry file \"$path\"!") 
      if !open(REG, $path)
   ;
   my $is_org=$/; $/="\n";
   while(<REG>) {
      # Skip everything until DEFINE marker...
      s/#.*//; s/^\s+//; s/\s+$//; next if !$_; 
      last if /^DEFINE:/i;
   }
   while(<REG>) {
      s/#.*//; s/^\s+//; s/\s+$//; next if !$_; 
      last if /^DATA:/i;
      ($k, $v) = split /\s*[= ]\s*/,$_,2;
      $k=~s/^\$//; $v=~s/^"(.*)"$/$1/;
      if ($v!~s/^'(.*)'$/$1/) {
         # parse environment
         my @check=(); while ($v=~/\$(\w+)/g) { push (@check, $1) }
         for (@check) { $v =~ s/\$$_/$ENV{$_}/g }
         # parse home tilde
         if (($v eq '~') || ($v=~/^~\//)) { 
            my $h=$ENV{HOME}||(getpwuid($<))[7]||"/"; $v=~s/^~/$h/; 
         }
      }
      $var{$k} = $v;
   }
   my ($name, $dest, $src, $style, @alias, $info);
   my %arg_s = (
      "name"=>\$name, "dest"=>\$dest, "src"=>\$src, 
      "style"=>\$style, "info"=>\$info
   );
   my %arg_a = ("alias"=>\@alias);
   $name=""; $dest=""; $src=""; $style=""; @alias=(); $info="";
   while(<REG>) {
      s/#.*//; s/^\s+//; s/\s+$//;
      if (!$_) {
         $S->_add_registry_entry (
            $name, $src, $dest, $style, \@alias, $info
         ) if $name;
         $name=""; $dest=""; $src=""; $style=""; @alias=(); $info=""; next;
      }
      ($k, $v) = split /\s*[: ]\s*/,$_,2;
      for (keys %var) {
         $v =~ s/\$$_/$var{$_}/g;
      }
      $k = lc($k);
      if ($arg_s{$k}) {
         ${$arg_s{$k}} = $v;
      } elsif ($arg_a{$k}) {
         push (@{$arg_a{$k}}, $v);
      }
   }
   $/=$is_org;
   close(REG);
   $S->_msg_fin("done") if $S->noise>2;
   $registry_loaded=1;
1}

sub _add_registry_entry {
   my ($S, $name, $src, $dest, $style, $aliasL, $info) = @_;
   $registry{$name} = {
      "ALIAS"	=> $aliasL ? [@$aliasL] : [],
      "DEST"	=> $dest   || "",
      "INFO"	=> $info   || "",
      "SRC"	=> $src    || "",
      "STYLE"	=> $style  || "",
   };
}

sub _dump_registry {
   my ($k, $v);
   print "\nDumping registry definition:\n";
   while (($k, $v) = each %registry) {
      print "Name: $k\n";
      printf "   src:   %s\n", $v->{"SRC"};
      printf "   style: %s\n", $v->{"STYLE"};
      printf "   dest:  %s\n", $v->{"DEST"};
      printf "   info:  %s\n", $v->{"INFO"};
      print  "   alias: " . join (", ", @{$v->{"ALIAS"}}) . "\n";
      print  "\n";
   }
   print "done.\n";
}

##
## --- misc ---------------------------------------------------------------
##

sub _get_standard_pathes {
   my @dir = ();
   my $dir;
   $MAP_Pathname =~ s/^\///;
   $MAP_Pathname =~ s/\/$//;
   foreach $dir (@INC) {
      $dir =~ s/\/$//;
      push (@dir, "$dir/$MAP_Pathname") if (-d "$dir/$MAP_Pathname");
   }
   @dir;
}

sub _get_path {
   my ($S, $path) = @_;
   return $S->_error("Cannot find mapfile base directory!") if !@MAP_Path;
   $path =~ s/^\/+//;
   for (@MAP_Path) {
      return "$_/$path" if -f "$_/$path";
   }
   "";
}

sub _list_to_intervals {
   my ($listR, $start, $end) = @_;
   my @split = ();
   my ($begin, $i, $partend);
   $i=$start;
   while ($i<=$end) {
      $begin = $i;
      $partend = $begin+254;
      while (
         ($i<$end) && 
         ($i<$partend) &&
         ($listR->[$i+1]==($listR->[$i]+1))
      ) { 
         $i++ 
      }
      push (@split, ($begin, $i));
      $i++;
   }
   \@split;
}

"Atomkraft? Nein, danke!"

__END__

=head1 NAME

Unicode::Map - maps charsets from and to UCS2 unicode 

ALPHA release of C<$Date: 1998/02/12 05:03:13 $>

=head1 SYNOPSIS

=over 4

use Unicode::Map();

=item 1. Standard case:

 I<$Map> = new Unicode::Map({ ID => "ISO-8859-1" });

 I<$_16bit> = I<$Map> -> to_unicode ("Hello world!");
   => $_16bit == "\0H\0e\0l\0l\0o\0 \0w\0o\0r\0l\0d\0!"

 I<$_8bit> = I<$Map> -> from_unicode (I<$_16bit>);
   => $_8bit == "Hello world!"

=item 2. If you need different charsets:

 I<$Map> = new Unicode::Map;

 I<$_16bit> = I<$Map> -> to_unicode ("ISO-8859-1", "Hello world!");
   => $_16bit == "\0H\0e\0l\0l\0o\0 \0w\0o\0r\0l\0d\0!"

 I<$_8bit> = I<$Map> -> from_unicode ("ISO-8859-7", I<$_16bit>);
   => $_8bit == "Hello world!"

=back

More methods and a more detailed description below.

=head1 DESCRIPTION

This module converts strings from and to 2-byte Unicode UCS2 format. 
Available character sets, their names and their aliases are defined in 
the file C<REGISTRY> in the Unicode::Map hierarchy. 

Character mapping is according to the data of binary mapfiles in Unicode::Map 
hierarchy. Binary mapfiles can also be created with this module, so that you
could install your specific character sets.

Normally it is sufficient to map 1 character to 1 unicode character and vice
versa. Apple defines some 1 character to n unicode character mappings, so 
that this handling is implemented also. 

Have a look at utility I<map> coming along with this. 

If you need neither C<n> chars -> C<m> chars mappings, nor 16 bit -> 16 bit 
mappings, I recommend to use the high performance 8 bit <-> 16 bit module 
Unicode::Map8 by Gisle Aas instead.

=head1 CONVERSION METHODS

=over 4

=item from_unicode

C<1>||C<0> = I<$Map> -> from_unicode ((I<$csid>,) I<$src>||I<\$src>, I<\$dest>)

I<$dest> = I<$Map> -> from_unicode ((I<$csid>,) I<$src>||I<\$src>)

Converts a UTF16 Unicode encoded string into I<$csid> character set 
representation. String is taken from I<$src>. If specified, converted string 
is stored in variable I<$dest>. If not specified it is simply returned.

Parameter I<$csid> has to be used, when it was omitted at constructor C<new>. 

You can use C<to8> as synonym for C<from_unicode>.

=item new

I<$Map> = new Unicode::Map()

Returns a new Map object. Method new can be initialized via an anonymous
hash with an instance I<$Startup> of OLE::Storage::Startup:

 I<$Map> = new Unicode::Map({ 
    ID      => I<$csid>,
    STARTUP => I<$Startup>
 })

The module then would send comments and error messages to I<$Startup>.
You can change the verbosity of comments with method noise. Module
Startup is in very early development and is packed among OLE::Storage 
distribution, it is not published separately.

=item noise

I<$Map> -> noise (I<$n>)

Defines the verbosity of messages to user sent via I<$Startup>. Can be no
messages at all (n=0), some information (n=1) or some more information
(n=3). Default is n=1.

=item reverse_unicode

I<$string> = I<$Map> -> reverse_unicode (I<$string>)

One Unicode character, precise one UCS2 (UTF16) character, consists of two
bytes. Therefore it is important, in which order these bytes are stored.
As far as I could figure out, Unicode characters are assumed to be in
"Network order" (0x1234 => 0x12, 0x34). Alas, many PC Windows documents
store Unicode characters internally in "Vax order" (0x1234 => 0x34, 0x12).
With this method you can convert "Vax mode" -> "Network mode" and vice versa.

If possible, reverse_unicode changes the original variable!

=item to_unicode

C<1>||C<0> = I<$Map> -> to_unicode ((I<$csid>,) I<$src>||I<\$src>, I<\$dest>)

I<$dest>   = I<$Map> -> to_unicode ((I<$csid>,) I<$src>||I<\$src>)

Converts a I<$csid> encoded string into UTF16 Unicode character set
representation. String is taken from I<$src>. If specified, converted string 
is stored in variable I<$dest>. If not specified it is simply returned.

Parameter I<$csid> has to be used, when it was omitted at constructor C<new>. 

You can use C<to16> as synonym for C<to_unicode>.

=back

=head1 MAINTAINANCE METHODS

=over 4

=item alias

I<@list> = I<$Map> -> alias (I<$csid>)

Returns a list of alias names of character set I<$csid>.

=item dest

I<$path> = I<$Map> -> dest (I<$csid>)

Returns the relative path of binary character mapping for character set 
I<$csid> according to REGISTRY file of Unicode::Map.

=item id

I<$real_id>||C<""> = I<$Map> -> id (I<$test_id>)

Returns a valid character set identifier I<$real_id>, if I<$test_id> is
a valid character set name or alias name according to REGISTRY file of 
Unicode::Map.

=item ids

I<@ids> = I<$Map> -> ids()

Returns a list of all character set names defined in REGISTRY file.

=item read_text_mapping

C<1>||C<0> = I<$Map> -> read_text_mapping (I<$csid>, I<$path>, I<$style>)

Read a text mapping of style I<$style> named I<$csid> from filename I<$path>.
The mapping then can be saved to a file with method: write_binary_mapping.
<$style> can be:

 style 	      description

 "unicode"    A text mapping as of ftp://ftp.unicode.org/MAPPINGS/
 ""           Same as "unicode"
 "reverse"    Similar to unicode, but both columns are switched
 "keld"       A text mapping as of ftp://dkuug.dk/i18n/charmaps/

=item src

I<$path> = I<$Map> -> src (I<$csid>)

Returns the path of textual character mapping for character set I<$csid> 
according to REGISTRY file of Unicode::Map.

=item style

I<$path> = I<$Map> -> style (I<$csid>)

Returns the style of textual character mapping for character set I<$csid> 
according to REGISTRY file of Unicode::Map.

=item write_binary_mapping

C<1>||C<0> = I<$Map> -> write_binary_mapping (I<$csid>, I<$path>)

Stores a mapping that has been loaded via method read_text_mapping in
file I<$path>.

=back

=head1 BINARY MAPPINGS

Structure of binary Mapfiles

Unicode character mapping tables have sequences of sequential key and
sequential value codes. This property is used to crunch the maps easily. 
n (0<n<256) sequential characters are represented as a bytecount n and
the first character code key_start. For these subsequences the according 
value sequences are crunched together, also. The value 0 is used to start
an extended information block (that is just partially implemented, though).

One could think of two ways to make a binary mapfile. First method would 
be first to write a list of all key codes, and then to write a list of all 
value codes. Second method, used here, appends to all partial key code lists
the according crunched value code lists. This makes value codes a little bit
closer to key codes. 

B<Note: the file format is still in a very liquid state. Neither rely on
that it will stay as this, nor that the description is bugless, nor that
all features are implemented.>

STRUCTURE:

=over 4

=item <main>:

   offset  structure     value

   0x00    word          0x27b8	(magic)
   0x02    @(<extended> || <submapping>)

The mapfile ends with extended mode <end> in main stream.

=item <submapping>:

   0x00    byte != 0     charsize1 (bits)
   0x01    byte          n1 number of chars for one entry
   0x02    byte          charsize2 (bits)
   0x03    byte          n2 number of chars for one entry
   0x04    @(<extended> || <key_seq> || <key_val_seq)

   bs1=int((charsize1+7)/8), bs2=int((charsize2+7)/8)

One submapping ends when <mapend> entry occurs.

=item <key_val_seq>:

   0x00    size=0|1|2|4  n, number of sequential characters 
   size    bs1           key1
   +bs1    bs2           value1
   +bs2    bs1           key2
   +bs1    bs2           value2
   ...

key_val_seq ends, if either file ends (n = infinite mode) or n pairs are
read.

=item <key_seq>:

   0x00    byte          n, number of sequential characters 
   0x01    bs1           key_start, first character of sequence
   1+bs1   @(<extended> || <val_seq>)

A key sequence starts with a byte count telling how long the sequence
is. It is followed by the key start code. After this comes a list of 
value sequences. The list of value sequences ends, if sum(m) equals n.

=item <val_seq>:

   0x00    byte          m, number of sequential characters
   0x01    bs2           val_start, first character of sequence

=item <extended>:

   0x00    byte          0
   0x01    byte          ftype
   0x02    byte          fsize, size of following structure
   0x03    fsize bytes   something

For future extensions or private use one can insert here 1..255 byte long 
streams. ftype can have values 30..255, values 0..29 are reserved. Modi
are not fully defined now and could change. They will be explained later.

=back

=head1 TO BE DONE

=over 4

=item - 

Something clever, when a character has no translation.

=item - 

Direct charset -> charset mapping.

=item - 

Velocity.

=item - 

Support for mappings according to RFC 1345.

=item - 

Something clever to include partial character sets to character sets.
This for those charset definitions, that by what reason ever don't like 
to include mappings for control codes.

=item - 

The "REGISTRY" concept is somehow weird...

=back

=head1 SEE ALSO

=over 4

=item -

File C<REGISTRY> and binary mappings in directory C<Unicode/Map> of your
perl library path 

=item -

recode(1), map(1), mkmapfile(1), Unicode::Map(3), Unicode::String(3), 
Unicode::CharName(3)

=item -

RFC 1345

=item -

Mappings at Unicode consortium ftp://ftp.unicode.org/MAPPINGS/

=item -

Registrated Internet character sets ftp://dkuug.dk/i18n/charmaps/

=back

=head1 AUTHOR

Martin Schwartz E<lt>F<schwartz@cs.tu-berlin.de>E<gt>

=cut

