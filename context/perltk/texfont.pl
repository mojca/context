eval '(exit $?0)' && eval 'exec perl -S $0 ${1+"$@"}' && eval 'exec perl -S $0 $argv:q'
        if 0;

# This is an example of a crappy unstructured file but once
# I know what should happen exactly, I will clean it up.

# todo : ttf (partially doen already)

#D \module
#D   [       file=texfont.pl,
#D        version=2003.08.08, % 2000.12.14
#D          title=Font Handling,
#D       subtitle=installing and generating,
#D         author=Hans Hagen ++,
#D           date=\currentdate,
#D      copyright={PRAGMA / Hans Hagen \& Ton Otten}]
#C
#C This module is part of the \CONTEXT\ macro||package and is
#C therefore copyrighted by \PRAGMA. See licen-en.pdf for
#C details.

#D For usage information, see \type {mfonts.pdf}.

#D Todo : copy afm/pfb from main to local files to ensure metrics
#D Todo : Wybo's help system
#D Todo : list of encodings [texnansi, ec, textext]

#D Thanks to George N. White III for solving a couple of bugs.
#D Thanks to Adam T. Lindsay for adding Open Type support.

use strict ;

my $savedoptions = join (" ",@ARGV) ;

use Config ;
use FindBin ;
use File::Copy ;
use Getopt::Long ;

$Getopt::Long::passthrough = 1 ; # no error message
$Getopt::Long::autoabbrev  = 1 ; # partial switch accepted

# Unless a user has specified an installation path, we take
# the dedicated font path or the local path.

## $dosish = ($Config{'osname'} =~ /dos|mswin/i) ;
my $dosish = ($Config{'osname'} =~ /^(ms)?dos|^os\/2|^(ms|cyg)win/i) ;

my $IsWin32 = ($^O =~ /MSWin32/i);

BEGIN {
  $IsWin32 = ($^O =~ /MSWin32/i);

  if ($IsWin32) {
    require Win32::API; import Win32::API;
  }
}

# great, glob changed to bsd glob in an incompatible way ... sigh, we now
# have to catch a failed glob returning the pattern

sub validglob {
    my @globbed = glob(shift) ;
    if ((@globbed) &&  (! -e $globbed[0])) {
        return () ;
    } else {
        return @globbed ;
    }
}

sub GetShortPathName {
    my ($filename) = @_;
    return $filename unless ($IsWin32) ;
    my $GetShortPathName = new Win32::API('kernel32', 'GetShortPathName', 'PPN', 'N');
    if(not defined $GetShortPathName) {
      die "Can't import API GetShortPathName: $!\n";
    }
    my $buffer = " " x 260;
    my $len = $GetShortPathName->Call($filename, $buffer, 260);
    return substr($buffer, 0, $len); }

my $installpath = "" ; my @searchpaths = () ;

if (defined($ENV{TEXMFLOCAL})) { $installpath = "TEXMFLOCAL" }
if (defined($ENV{TEXMFFONTS})) { $installpath = "TEXMFFONTS" }

#  ($installpath eq "") { $installpath = "TEXMFFONTS" } # redundant
if ($installpath eq "") { $installpath = "TEXMFLOCAL" } # redundant

@searchpaths = ('TEXMFFONTS','TEXMFLOCAL','TEXMFMAIN') ;

my $encoding        = "texnansi" ;
my $vendor          = "" ;
my $collection      = "" ;
my $fontroot        = "" ; #/usr/people/gwhite/texmf-fonts" ;
my $help            = 0 ;
my $makepath        = 0 ;
my $show            = 0 ;
my $install         = 0 ;
my $sourcepath      = "." ;
my $passon          = "" ;
my $extend          = "" ;
my $narrow          = "" ;
my $slant           = "" ;
my $caps            = "" ;
my $noligs          = 0 ;
my $test            = 0 ;
my $virtual         = 0 ;
my $novirtual       = 0 ;
my $listing         = 0 ;
my $remove          = 0 ;
my $expert          = 0 ;

my $fontsuffix  = "" ;
my $namesuffix  = "" ;

my $batch = "" ;

my $weight = "" ;
my $width = "" ;

my $preproc         = 0 ;     # atl: formerly OpenType switch
my $variant         = "" ;    # atl: encoding variant
my $extension       = "pfb" ; # atl: default font extension
my $lcdf            = "" ;    # atl: trigger for lcdf otftotfm

# todo: parse name for style, take face from command line
#
# @Faces  = ("Serif","Sans","Mono") ;
# @Styles = ("Slanted","Italic","Bold","BoldSlanted","BoldItalic") ;
#
# for $fac (@Faces) { for $sty (@Styles) { $FacSty{"$fac$sty"} = "" } }

&GetOptions
  ( "help"         => \$help,
    "makepath"     => \$makepath,
    "noligs"       => \$noligs,
    "show"         => \$show,
    "install"      => \$install,
    "encoding=s"   => \$encoding,
    "variant=s"    => \$variant,  # atl: used as a suffix to $encfile only
    "vendor=s"     => \$vendor,
    "collection=s" => \$collection,
    "fontroot=s"   => \$fontroot,
    "sourcepath=s" => \$sourcepath,
    "passon=s"     => \$passon,
    "slant=s"      => \$slant,
    "extend=s"     => \$extend,
    "narrow=s"     => \$narrow,
    "listing"      => \$listing,
    "remove"       => \$remove,
    "test"         => \$test,
    "virtual"      => \$virtual,
    "novirtual"    => \$novirtual,
    "caps=s"       => \$caps,
    "batch"        => \$batch,
    "weight=s"     => \$weight,
    "width=s"      => \$width,
    "expert"       => \$expert,
    "preproc"      => \$preproc,  # atl: trigger conversion to pfb
    "lcdf"         => \$lcdf ) ;  # atl: trigger use of lcdf fonttoools

# for/from Fabrice:

my $own_path = "$FindBin::Bin/" ;
$FindBin::RealScript =~ m/([^\.]*)(\.pl|\.bat|\.exe|)/io ;
my $own_name = $1 ;
my $own_type = $2 ;
my $own_stub  = "" ;
if ($own_type =~ /pl/oi) { $own_stub = "perl " }

# so we can use both combined

if ($lcdf) { $novirtual = 1 }
if (!$novirtual) { $virtual = 1 }

# A couple of routines.

sub report
  { my $str = shift ;
    $str =~ s/  / /goi ;
    if ($str =~ /(.*?)\s+([\:\/])\s+(.*)/o)
      { if ($1 eq "") { $str = " " } else { $str = $2 }
        print sprintf("%22s $str %s\n",$1,$3) } }

sub error
  { report("processing aborted : " . shift) ;
    print "\n" ;
    report "--help : show some more info" ;
    exit }

# The banner.

print "\n" ;
report ("TeXFont 1.8 - ConTeXt / PRAGMA ADE 2000-2003") ;
print "\n" ;

# Handy for scripts: one can provide a preferred path, if it
# does not exist, the current path is taken.

if (!(-d $sourcepath)&&($sourcepath ne 'auto')) { $sourcepath = "." }

# Let's make multiple masters if requested.

sub create_mm_font
  { my ($name,$weight,$width) = @_ ; my $flag = my $args = my $tags = "" ;
    my $ok ;
    if ($name ne "")
      { report ("mm source file : $name") }
    else
      { error ("missing mm source file") }
    if ($weight ne "")
      { report ("weight : $weight") ;
        $flag .= " --weight=$weight " ;
        $tags .= "-weight-$weight" }
    if ($width ne "")
      { report ("width : $width") ;
        $flag .= " --width=$width " ;
        $tags .= "-width-$width" }
    error ("no specification given") if ($tags eq "") ;
    error ("no amfm file found") unless (-f "$sourcepath/$name.amfm") ;
    error ("no pfb file found") unless (-f "$sourcepath/$name.pfb") ;
    $args = "$flag --precision=5 --kern-precision=0 --output=$sourcepath/$name$tags.afm" ;
    $ok = `mmafm $args $sourcepath/$name.amfm` ; chomp $ok ;
    if ($ok ne "") { report ("warning $ok") }
    $args = "$flag --precision=5 --output=$sourcepath/$name$tags.pfb" ;
    $ok = `mmpfb $args $sourcepath/$name.pfb` ; chomp $ok ;
    if ($ok ne "") { report ("warning $ok") }
    report ("mm result file : $name$tags") }

if (($weight ne "")||($width ne ""))
  { create_mm_font($ARGV[0],$weight,$width) ;
    exit }

# go on

if (($listing||$remove)&&($sourcepath eq "."))
  { $sourcepath = "auto" }

if ($fontroot eq "")
  { if ($dosish)
      { $fontroot = `kpsewhich --expand-path=\$$installpath` }
    else
      { $fontroot = `kpsewhich --expand-path=\\\$$installpath` }
    chomp $fontroot }


if ($fontroot =~ /\s+/)  # needed for windows, spaces in name
  { $fontroot = &GetShortPathName($fontroot) } # but ugly when not needed

if ($test)
  { $vendor = $collection = "test" ;
    $install = 1 }

if (($slant  ne "") && ($slant  !~ /\d/)) { $slant  = "0.167" }
if (($extend ne "") && ($extend !~ /\d/)) { $extend = "1.200" }
if (($narrow ne "") && ($narrow !~ /\d/)) { $narrow = "0.800" }
if (($caps   ne "") && ($caps   !~ /\d/)) { $caps   = "0.800" }

$encoding   = lc $encoding ;
$vendor     = lc $vendor ;
$collection = lc $collection ;

if ($encoding =~ /default/oi) { $encoding = "texnansi" }

my $lcfontroot = lc $fontroot ;

# Test for help asked.

if ($help)
  { report "--fontroot=path     : texmf font root (default: $lcfontroot)" ;
    report "--sourcepath=path   : when installing, copy from this path (default: $sourcepath)" ;
    report "--sourcepath=auto   : locate and use vendor/collection" ;
    print  "\n" ;
    report "--vendor=name       : vendor name/directory" ;
    report "--collection=name   : font collection" ;
    report "--encoding=name     : encoding vector (default: $encoding)" ;
    report "--variant=name      : encoding variant (.enc file or otftotfm features)" ;
    print  "\n" ;
    report "--slant=s           : slant glyphs in font by factor (0.0 - 1.5)" ;
    report "--extend=s          : extend glyphs in font by factor (0.0 - 1.5)" ;
    report "--caps=s            : capitalize lowercase chars by factor (0.5 - 1.0)" ;
    report "--noligs            : remove ligatures" ;
    print  "\n" ;
    report "--install           : copy files from source to font tree" ;
    report "--listing           : list files on auto sourcepath" ;
    report "--remove            : remove files on auto sourcepath" ;
    report "--makepath          : when needed, create the paths" ;
    print  "\n" ;
    report "--test              : use test paths for vendor/collection" ;
    report "--show              : run tex on texfont.tex" ;
    print  "\n" ;
    report "--batch             : process given batch file" ;
    print  "\n" ;
    report "--weight            : multiple master weight" ;
    report "--width             : multiple master width" ;
    print  "\n" ;
    report "--expert            : also handle expert fonts" ;
    print  "\n" ;
    report "--preproc           : pre-process ttf/otf, converting them to pfb" ;
    report "--lcdf              : use lcdf fonttools to create virtual encoding" ;
    exit }

if (($batch)||(($ARGV[0]) && ($ARGV[0] =~ /.+\.dat$/io)))
  { my $batchfile = $ARGV[0] ;
    unless (-f $batchfile)
      { if ($batchfile !~ /\.dat$/io) { $batchfile .= ".dat" } }
    unless (-f $batchfile)
      { report ("trying to locate : $batchfile") ;
        $batchfile = `kpsewhich -progname=context --format="other text files" $batchfile` ;
        chomp $batchfile }
    error ("unknown batch file $batchfile") unless -e $batchfile ;
    report ("processing batch file : $batchfile") ;
    my $select = (($vendor ne "")||($collection ne "")) ;
    my $selecting = 0 ;
    if (open(BAT, $batchfile))
      { while (<BAT>)
          { chomp ;
            next if (/^\s*$/io) ;
            if ($select)
              { if ($selecting)
                  { if (/^\s*[\#\%]/io) { if (!/\-\-/o) { last } else { next } } }
                elsif ((/^\s*[\#\%]/io)&&(/$vendor/i)&&(/$collection/i))
                  { $selecting = 1 ; next }
                else
                  { next } }
            else
              { next if (/^\s*[\#\%]/io) ;
                next unless (/\-\-/oi) }
                s/\s+/ /gio ;
                s/(--en.*\=)\?/$1$encoding/io ;
                report ("batch line : $_") ;
              # system ("perl $0 --fontroot=$fontroot $_") }
	        my $own_quote = ( $own_path =~ m/^[^\"].* / ? "\"" : "" );
                system ("$own_stub$own_quote$own_path$own_name$own_type$own_quote --fontroot=$fontroot $_") }
            close (BAT) }
    exit }

error ("unknown vendor     $vendor")     unless    $vendor ;
error ("unknown collection $collection") unless    $collection ;
error ("unknown tex root   $lcfontroot") unless -d $fontroot ;

my $varlabel = $variant ;
if ($lcdf)
{ $varlabel =~ s/,/-/goi ;
  $varlabel =~ tr/a-z/A-Z/ }

if ($varlabel ne "")
{ $varlabel = "-$varlabel" }

my $identifier = "$encoding$varlabel-$vendor-$collection" ;

my $outlinepath = $sourcepath ; my $path = "" ;

if ($sourcepath eq "auto")
  { foreach my $root (@searchpaths)
      { if ($dosish)
          { $path = `kpsewhich -expand-path=\$$root` }
        else
          { $path = `kpsewhich -expand-path=\\\$$root` }
        chomp $path ;
	if ($preproc)
          { $sourcepath = "$path/fonts/truetype/$vendor/$collection" }
	else
          { $sourcepath = "$path/fonts/afm/$vendor/$collection" }
        unless (-d $sourcepath)
          { my $ven = $vendor ; $ven =~ s/(........).*/$1/ ;
            my $col = $collection ; $col =~ s/(........).*/$1/ ;
            $sourcepath = "$path/fonts/afm/$ven/$col" ;
            if (-d $sourcepath)
              { $vendor = $ven ; $collection = $col } }
        $outlinepath = "$path/fonts/type1/$vendor/$collection" ;
        if (-d $sourcepath)
          { # $install = 0 ;  # no copy needed
            $makepath = 1 ; # make on local if needed
	    my @files = validglob("$sourcepath/*.afm") ;
	    if ($preproc)
	      { @files = validglob("$sourcepath/*.otf") ;
	        report("locating : otf files") }
	    unless (@files)
              { @files = validglob("$sourcepath/*.ttf") ;
	        report("locating : ttf files") }
            if (@files)
              { if ($listing)
                  { report ("fontpath : $sourcepath" ) ;
                    print "\n" ;
                    foreach my $file (@files)
                      { if (open(AFM,$file))
                          { my $name = "unknown name" ;
                            while (<AFM>)
                              { chomp ;
                                if (/^fontname\s+(.*?)$/oi)
                                  { $name = $1 ; last } }
                            close (AFM) ;
			    if ($preproc)
                             { $file =~ s/.*\/(.*)\..tf/$1/io }
			    else
                             { $file =~ s/.*\/(.*)\.afm/$1/io }
                            report ("$file : $name") } }
                    exit }
                elsif ($remove)
                  { error ("no removal from : $root") if ($root eq 'TEXMFMAIN') ;
                    foreach my $file (@files)
                      { if ($preproc)
                          { $file =~ s/.*\/(.*)\..tf/$1/io }
			else
                          { $file =~ s/.*\/(.*)\.afm/$1/io }
                        foreach my $sub ("tfm","vf")
                          { foreach my $typ ("","-raw")
                              { my $nam = "$path/fonts/$sub/$vendor/$collection/$encoding$varlabel$typ-$file.$sub" ;
                                if (-s $nam)
                                  { report ("removing : $encoding$varlabel$typ-$file.$sub") ;
                                    unlink $nam } } } }
                    my $nam = "$encoding$varlabel-$vendor-$collection.tex" ;
                    if (-e $nam)
                      { report ("removing : $nam") ;
                        unlink "$nam" }
                    my $mapfile = "$encoding$varlabel-$vendor-$collection" ;
                    my $maproot = "$fontroot/pdftex/config/";
                    if (-e "$maproot$mapfile.map")
                      { report ("renaming : $mapfile.map -> $mapfile.bak") ;
                        unlink "$maproot$mapfile.bak" ;
                        rename "$maproot$mapfile.map", "$maproot$mapfile.bak" }
                    exit }
                else
                  { last } } } }
    error ("unknown subpath ../fonts/afm/$vendor/$collection") unless -d $sourcepath }

error ("unknown source path $sourcepath") unless -d $sourcepath ;
error ("unknown option $ARGV[0]")         if ($ARGV[0] =~ /\-\-/) ;

my $afmpath = "$fontroot/fonts/afm/$vendor/$collection" ;
my $tfmpath = "$fontroot/fonts/tfm/$vendor/$collection" ;
my $vfpath  = "$fontroot/fonts/vf/$vendor/$collection" ;
my $pfbpath = "$fontroot/fonts/type1/$vendor/$collection" ;
my $ttfpath = "$fontroot/fonts/truetype/$vendor/$collection" ;
my $pdfpath = "$fontroot/pdftex/config" ;
my $encpath = "$fontroot/dvips/local" ;

# are not on local path ! ! ! !

foreach my $path ($afmpath, $pfbpath)
  { my @gzipped = <$path/*.gz> ;
    foreach my $file (@gzipped)
      { print "file = $file\n";
	system ("gzip -d $file") } }
system ("mktexlsr $fontroot");  # needed ?

sub do_make_path
  { my $str = shift ; mkdir $str, 0755 unless -d $str }

sub make_path
  { my $str = shift ;
    do_make_path("$fontroot/fonts") ;
    do_make_path("$fontroot/fonts/$str") ;
    do_make_path("$fontroot/fonts/$str/$vendor") ;
    do_make_path("$fontroot/fonts/$str/$vendor/$collection") }

if ($makepath&&$install)
  { make_path ("afm") ; make_path ("type1") }

do_make_path("$fontroot/pdftex") ;
do_make_path("$fontroot/pdftex/config") ;

if ($lcdf)
  { do_make_path("$fontroot/dvips") ;
    do_make_path("$fontroot/dvips/local") }

make_path ("vf") ;
make_path ("tfm") ;

if ($install)
  { error ("unknown afm path $afmpath") unless -d $afmpath ;
    error ("unknown pfb path $pfbpath") unless -d $pfbpath }

error ("unknown tfm path $tfmpath") unless -d $tfmpath ;
error ("unknown vf  path $vfpath" ) unless -d $vfpath  ;
error ("unknown pdf path $pdfpath") unless -d $pdfpath ;

my $mapfile = "$identifier.map" ;
my $bakfile = "$identifier.bak" ;
my $texfile = "$identifier.tex" ;

                report  "encoding vector : $encoding" ;
if ($variant) { report "encoding variant : $variant" }
                report      "vendor name : $vendor" ;
                report  "    source path : $sourcepath" ;
                report  "font collection : $collection" ;
                report  "texmf font root : $lcfontroot" ;
                report  "pdftex map file : $mapfile" ;

if ($install)        { report "source path : $sourcepath" }

my $fntlist = my $pattern = "" ;

my $runpath = $sourcepath ;

my @files ;

sub globafmfiles
  { my ($runpath, $pattern)  = @_ ;
    my @files = validglob("$runpath/$pattern.afm") ;
    if ($preproc && !$lcdf)
      { @files = validglob("$runpath/$pattern.*tf") ;
        report("locating otf files : using pattern $pattern");
        unless (@files)
          { @files = validglob("$sourcepath/$pattern.ttf") ;
	        report("locating ttf files : using pattern $pattern") }
      #     if ($lcdf) { $extension = "otf" }
          }
    if (@files) # also elsewhere
      { report("locating afm files : using pattern $pattern") }
    else
      { @files = validglob("$runpath/$pattern.ttf") ;
	if (@files)
	  { report("locating afm files : using ttf files") ;
	    $extension = "ttf" ;
	    foreach my $file (@files)
               { $file =~ s/\.ttf$//io ;
		report ("generating afm file : $file.afm") ;
		system("ttf2afm $file.ttf -o $file.afm") }
	    @files = validglob("$runpath/$pattern.afm") }
	else # try doing the pre-processing earlier
	  { report("locating afm files : using otf files") ;
	    $extension = "otf" ;
	    @files = validglob("$runpath/$pattern.otf") ;
	    foreach my $file (@files)
	      { $file =~ s/\.otf$//io ;
		report ("generating afm file : $file.afm") ;
		preprocess_font("$file.otf", "$file.bdf") ;
		if ($preproc)
		{ system("cfftot1 --output=$file.pfb $file.otf") ;
		  report("converting : $file.otf to $file.pfb") ;
	        }
	      }
      	    if ($lcdf)
	    { @files = validglob("$runpath/$pattern.otf") }
	    else
	    { @files = validglob("$runpath/$pattern.afm") }
	  }
       }
    return @files }


if ($ARGV[0] ne "")
  { $pattern = $ARGV[0] ;
    report ("processing files : all in pattern $ARGV[0]") ;
    @files = globafmfiles($runpath,$pattern) }
elsif ("$extend$narrow$slant$caps" ne "")
  { error ("transformation needs file spec") }
else
  { $pattern = "*" ;
    report ("processing files : all on afm path") ;
    @files = globafmfiles($runpath,$pattern) }

sub copy_files
  { my ($suffix,$sourcepath,$topath) = @_ ;
    my @files = validglob("$sourcepath/$pattern.$suffix") ;
    return if ($topath eq $sourcepath) ;
    report ("copying files : $suffix") ;
    foreach my $file (@files)
      { my $ok = $file =~ /(.*)\/(.+?)\.(.*)/ ;
        my ($path,$name,$suffix) = ($1,$2,$3) ;
        unlink "$topath/$name.$suffix" ;
        report ("copying : $name.$suffix") ;
        copy ($file,"$topath/$name.$suffix") } }

if ($install)
  { copy_files("afm",$sourcepath,$afmpath) ;
#   copy_files("tfm",$sourcepath,$tfmpath) ; # raw supplied names
    copy_files("pfb",$outlinepath,$pfbpath) ;
    if ($extension eq "ttf")
      { make_path("truetype") ;
        copy_files("ttf",$sourcepath,$ttfpath) }
    if ($extension eq "otf")
      { make_path("truetype") ;
	copy_files("otf",$sourcepath,$ttfpath) } }

error ("no afm files found") unless @files ;

my $map = my $tex = 0 ; my $mapdata = my $texdata = "" ;

copy ("$pdfpath/$mapfile","$pdfpath/$bakfile") ;

if (open (MAP,"<$pdfpath/$mapfile"))
  { report ("extending map file : $pdfpath/$mapfile") ;
    while (<MAP>) { unless (/^\%/o) { $mapdata .= $_ } }
    close (MAP) }
else
  { report ("no map file at : $pdfpath/$mapfile") }

if (open (TEX,"<$texfile"))
  { while (<TEX>) { unless (/stoptext/o) { $texdata .= $_ } }
    close (TEX) }

$map = open (MAP,">$mapfile") ;
$tex = open (TEX,">$texfile") ;

unless ($map) { report "warning : can't open $mapfile" }
unless ($tex) { report "warning : can't open $texfile" }

if ($map)
  { print MAP "% This file is generated by the TeXFont Perl script.\n" ;
    print MAP "%\n" ;
    print MAP "% You need to add the following line to pdftex.cfg:\n" ;
    print MAP "%\n" ;
    print MAP "%   map +$mapfile\n" ;
    print MAP "%\n" ;
    print MAP "% Alternatively in your TeX source you can say:\n" ;
    print MAP "%\n" ;
    print MAP "%   \\pdfmapfile\{+$mapfile\}\n" ;
    print MAP "%\n" ;
    print MAP "% In ConTeXt you can best use:\n" ;
    print MAP "%\n" ;
    print MAP "%   \\loadmapfile\[$mapfile\]\n\n" }

if ($tex)
  { if ($texdata eq "")
      { print TEX "% output=pdftex interface=en\n" ;
        print TEX "\n" ;
        print TEX "\\usemodule[fnt-01]\n" ;
        print TEX "\n" ;
        print TEX "\\loadmapfile[$mapfile]\n" ;
        print TEX "\n" ;
        print TEX "\\starttext\n\n" }
    else
      { print TEX "$texdata" ;
        print TEX "\n\%appended section\n\n\\page\n\n" } }

my $shape = "" ;

if ($noligs)
  { report ("ligatures : removed") ;
    $fontsuffix .= "-unligatured" ;
    $namesuffix .= "-NoLigs" }

if ($caps ne "")
  {    if ($caps <0.5) { $caps = 0.5 }
    elsif ($caps >1.0) { $caps = 1.0 }
    $shape .= " -c $caps " ;
    report ("caps factor : $caps") ;
    $fontsuffix .= "-capitalized-" . int(1000*$caps)  ;
    $namesuffix .= "-Caps" }

if ($extend ne "")
  { if    ($extend<0.0) { $extend = 0.0 }
    elsif ($extend>1.5) { $extend = 1.5 }
    report ("extend factor : $extend") ;
    $shape .= " -e $extend " ;
    $fontsuffix .= "-extended-" . int(1000*$extend) ;
    $namesuffix .= "-Extended" }

if ($narrow ne "") # goodie
  { $extend = $narrow ;
    if    ($extend<0.0) { $extend = 0.0 }
    elsif ($extend>1.5) { $extend = 1.5 }
    report ("narrow factor : $extend") ;
    $shape .= " -e $extend " ;
    $fontsuffix .= "-narrowed-" . int(1000*$extend) ;
    $namesuffix .= "-Narrowed" }

if ($slant ne "")
  {    if ($slant <0.0) { $slant = 0.0 }
    elsif ($slant >1.5) { $slant = 1.5 }
    report ("slant factor : $slant") ;
    $shape .= " -s $slant " ;
    $fontsuffix .= "-slanted-" . int(1000*$slant) ;
    $namesuffix .= "-Slanted" }

sub removeligatures
  { my $filename = shift ; my $skip = 0 ;
    copy ("$filename.vpl","$filename.tmp") ;
    if ((open(TMP,"<$filename.tmp"))&&(open(VPL,">$filename.vpl")))
      { report "removing ligatures : $filename" ;
        while (<TMP>)
         { chomp ;
           if ($skip)
             { if (/^\s*\)\s*$/o) { $skip = 0 ; print VPL "$_\n" } }
           elsif (/\(LIGTABLE/o)
             { $skip = 1 ; print VPL "$_\n" }
           else
             { print VPL "$_\n" } }
        close(TMP) ; close(VPL) }
    unlink ("$filename.tmp") }

my $raw = my $use = my $maplist = my $texlist = my $report = "" ;

$use = "$encoding$varlabel-" ; $raw = $use . "raw-" ;

my $encfil = "" ;

if ($encoding ne "") # evt -progname=context
  { $encfil = `kpsewhich -progname=pdftex $encoding$varlabel.enc` ;
    chomp $encfil ; if ($encfil eq "") { $encfil = "$encoding$varlabel.enc" } }

sub preprocess_font
  { my ($infont,$pfbfont) = @_ ;
    if ($infont ne "")
      { report ("otf/ttf source file : $infont") ;
        report ("destination file : $pfbfont") ; }
    else
      { error ("missing otf/ttf source file") }
    open (CONVERT, "| pfaedit -script -") || error ("couldn't open pipe to pfaedit") ;
    report ("pre-processing with : pfaedit") ;
    print CONVERT "Open('$infont');\n Generate('$pfbfont', '', 1) ;\n" ;
    close (CONVERT) }

foreach my $file (@files)
  { my $option = my $slant = my $extend = my $vfstr = my $encstr = "" ;
    my $strange = "" ; my ($rawfont,$cleanfont,$restfont) ;
    $file = $file ;
    my $ok = $file =~ /(.*)\/(.+?)\.(.*)/ ;
    my ($path,$name,$suffix) = ($1,$2,$3) ;
    # remove trailing _'s
    my $fontname = $name ;
    my $cleanname = $fontname ;
    $cleanname =~ s/\_//gio ;
    # atl: pre-process an opentype or truetype file by converting to pfb
    if ($preproc && !$lcdf)
      { unless (-f "$afmpath/$cleanname.afm" && -f "$pfbpath/$cleanname.pfb")
          { preprocess_font("$path/$name.$suffix", "$pfbpath/$cleanname.pfb") ;
            rename("$pfbpath/$cleanname.afm", "$afmpath/$cleanname.afm")
	      || error("couldn't move afm product of pre-process.") }
        $path = $afmpath ;
        $file = "$afmpath/$cleanname.afm" }
    # cleanup
    foreach my $suf ("tfm", "vf", "vpl")
      { unlink "$raw$cleanname$fontsuffix.$suf" ;
        unlink "$use$cleanname$fontsuffix.$suf" }
    unlink "texfont.log" ;
    # set switches
    if ($encoding ne "")
      { $encstr = " -T $encfil" }
    if ($caps ne "")
      { $vfstr = " -V $raw$cleanname$fontsuffix" }
    else # if ($virtual)
      { $vfstr = " -v $raw$cleanname$fontsuffix" }
    my $font = "";
    # let's see what we have here (we force texnansi.enc to avoid error messages)
    if ($lcdf)
      { ( my $fileafm = $file ) =~ s/\.otf$/\.afm/ ;
        $font = `afm2tfm $fileafm -p texnansi.enc texfont.tfm` ;
        unlink $fileafm }
    else
      { $font = `afm2tfm $file -p texnansi.enc texfont.tfm` }
    unlink "texfont.tfm" ;
    if ($font =~ /(math|expert)/io) { $strange = lc $1 }
    ($rawfont,$cleanfont,$restfont) = split(/\s/,$font) ;
    $cleanfont =~ s/\_/\-/goi ;
    $cleanfont =~ s/\-+$//goi ;
    print "\n" ;
    if (($strange eq "expert")&&($expert))
      { report ("font identifier : $cleanfont$namesuffix -> $strange -> tfm") }
    elsif ($strange ne "")
      { report ("font identifier : $cleanfont$namesuffix -> $strange -> skipping") }
    elsif ($virtual)
      { report ("font identifier : $cleanfont$namesuffix -> text -> tfm + vf") }
    else
      { report ("font identifier : $cleanfont$namesuffix -> text -> tfm") }
    # don't handle strange fonts
    if ($strange eq "")
      { # atl: experimental support for lcdf otftotfm
        if ($lcdf && $extension eq "otf")
          { # no vf, bypass afm, use otftotfm to get encoding and tfm
            my $varstr = my $encout = my $tfmout = "" ;
            report "processing files : otf -> tfm + enc" ;
            if ($encoding ne "")
              { $encfil = `kpsewhich -progname=pdftex $encoding.enc` ;
                chomp $encfil ; if ($encfil eq "") { $encfil = "$encoding.enc" }
                $encstr = " -e $encfil " }
            if ($variant ne "")
              { ( $varstr = $variant ) =~ s/,/ -f /goi ;
                $varstr = " -f $varstr" }
            $encout = "$encpath/$use$cleanfont.enc" ;
            if (-e $encout)
              { report ("renaming : $encout -> $use$cleanfont.bak") ;
                unlink "$encpath/$use$cleanfont.bak" ;
                rename $encout, "$encpath/$use$cleanfont.bak" }
	    unlink "texfont.map" ;
            $tfmout = "$use$cleanfont" ;
            my $otfcommand = "otftotfm -a $varstr $encstr $shape --name=\'$tfmout\' --encoding-dir=\'$encpath/\' --tfm-dir=\'$tfmpath/\' --vf-dir=\'$vfpath/\' --no-type1 --map-file=./texfont.map \'$file\'" ;
            print "$otfcommand\n" ;
            system("$otfcommand") ;
#	    $namesuffix = "--base" ; #atl: lcdf currently appends --base to the filename...sometimes
            $encfil = $encout }
	else
	  { # generate tfm and vpl, $file is on afm path
            report "generating raw tfm/vpl : $raw$cleanname$fontsuffix (from $cleanname)" ;
            my $font = `afm2tfm $file $shape $passon $encstr $vfstr $raw$cleanname$fontsuffix` ;
            # generate vf file if needed
            chomp $font ;
            if ($font =~ /.*?([\d\.]+)\s*ExtendFont/io) { $extend = $1 }
            if ($font =~ /.*?([\d\.]+)\s*SlantFont/io)  { $slant  = $1 }
            if ($extend ne "") { $option .= " $1 ExtendFont " }
            if ($slant ne "")  { $option .= " $1 SlantFont " }
            if ($noligs) { removeligatures("$raw$cleanname$fontsuffix") }
            if ($virtual)
              { report "generating new vf : $use$cleanname$fontsuffix (from $raw$cleanname)" ;
                my $ok = `vptovf $raw$cleanname$fontsuffix.vpl $use$cleanname$fontsuffix.vf $use$cleanname$fontsuffix.tfm ` }
            else
              { report "generating new tfm : $use$cleanname$fontsuffix (from $raw$cleanname)" ;
                my $ok = `pltotf $raw$cleanname$fontsuffix.vpl $use$cleanname$fontsuffix.tfm ` } } }
    elsif (-e "$sourcepath/$cleanname.tfm" )
      { report "using existing tfm : $cleanname.tfm" }
    elsif (($strange eq "expert")&&($expert))
      { report "creating tfm file : $cleanname.tfm" ;
        my $font = `afm2tfm $file $cleanname.tfm` }
    else
      { report "use supplied tfm : $cleanname" }
    # report results
    ($rawfont,$cleanfont,$restfont) = split(/\s/,$font) ;
    $cleanfont =~ s/\_/\-/goi ;
    $cleanfont =~ s/\-+$//goi ;
    # copy files
    my $usename = "$use$cleanname$fontsuffix" ;
    my $rawname = "$raw$cleanname$fontsuffix" ;
    if ($lcdf eq "")
    { if ($strange ne "")
        { unlink "$vfpath/$cleanname.vf", "$tfmpath/$cleanname.tfm" ;
          copy ("$cleanname.tfm","$tfmpath/$cleanname.tfm") ;
          # or when available, use vendor one :
          copy ("$sourcepath/$cleanname.tfm","$tfmpath/$cleanname.tfm") }
      elsif ($virtual)
        { unlink "$vfpath/$rawname.vf", "$vfpath/$usename.vf" ;
          unlink "$tfmpath/$rawname.tfm", "$tfmpath/$usename.tfm" ;
          copy ("$usename.vf" ,"$vfpath/$usename.vf") ;
          copy ("$rawname.tfm","$tfmpath/$rawname.tfm") ;
          copy ("$usename.tfm","$tfmpath/$usename.tfm") }
      else
        { unlink "$vfpath/$usename.vf", "$tfmpath/$usename.tfm" ;
          # slow but prevents conflicting vf's
          my $rubish = `kpsewhich $usename.vf` ; chomp $rubish ;
          if ($rubish ne "") { unlink $rubish }
          #
          copy ("$usename.tfm","$tfmpath/$usename.tfm") } }
    # cleanup
    foreach my $suf ("tfm", "vf", "vpl")
      { unlink "$rawname.$suf", unlink "$usename.$suf" ;
        unlink "$cleanname.$suf", unlink "$fontname.$suf" ;
        unlink "$fontname$fontsuffix.$suf" }
    # add line to maps file
    $option =~ s/^\s+(.*)/$1/o ;
    $option =~ s/(.*)\s+$/$1/o ;
    $option =~ s/  / /o ;
    if ($option ne "")
      { $option = "\"$option\" 4" }
    else
      { $option = "4" }
    # adding cleanfont is kind of dangerous
    my $thename = my $str = my $theencoding = "" ;
    if ($strange ne "")
      { $thename = $cleanname ; $theencoding = "" ; }
    elsif ($lcdf)
      { $thename = $usename ; $theencoding = " $encoding$varlabel-$cleanname.enc" }
    elsif ($virtual)
      { $thename = $rawname ; $theencoding = " $encoding$varlabel.enc" }
    else
      { $thename = $usename ; $theencoding = " $encoding$varlabel.enc" }
    # quit rest if no type 1 file
    my $pfb_sourcepath = $sourcepath ;
    $pfb_sourcepath =~ s@/afm/@/type1/@ ;
    unless ((-e "$pfbpath/$fontname.$extension")||
            (-e "$pfb_sourcepath/$fontname.$extension")||
            (-e "$sourcepath/$fontname.$extension")||
	    (-e "$ttfpath/$fontname.$extension"))
     { if ($tex) { $report .= "missing file: \\type \{$fontname.pfb\}\n" }
       report ("missing pfb file : $fontname.pfb") }
    # now add entry to map
    if ($strange eq "")
      { if ($extension eq "otf")
          { if ($lcdf)
	    { my $mapline = "";
	      if (open(ALTMAP,"texfont.map"))
	      { while (<ALTMAP>)
		{ chomp ;
		  # atl: we assume this b/c we always force otftotfm --no-type1
		  if (/<<(.*)\.otf$/oi)
		  { $mapline = $_ ; last } }
		close(ALTMAP) }
	      else
  	        { report("no mapfile from otftotfm : texfont.map") }
	      if ($preproc)
 	        { $mapline =~ s/^(\S+)/$1 </;
	          $mapline =~ s/<<(\S+)\.otf$// }
	      else
	        { $mapline =~ s/<<(\S+)\.otf$/<< $ttfpath\/$fontname.$extension/ }
	      $str = "$mapline\n" }
	    else
	    { if ($preproc)
                { $str = "$thename $cleanfont $option < $fontname.pfb$theencoding\n"}
              else
              # PdfTeX can't subset OTF files, so we have to include the whole thing
              # It looks like we also need to be explicit on where to find the file
	        { $str = "$thename $cleanfont $option << $ttfpath/$fontname.$extension <[$theencoding\n" } } }
	else
	{ $str = "$thename $cleanfont $option < $fontname.$extension$theencoding\n" } }
    else
      { $str = "$thename $cleanfont < $fontname.$extension\n" }
    if ($map) # check for redundant entries
      { $mapdata =~ s/^$thename\s.*?$//gmis ;
        $maplist .= $str ;
        $mapdata .= $str }
    # write lines to tex file
    if (($strange eq "expert")&&($expert))
      { $fntlist .= "\\definefontsynonym[$cleanfont$namesuffix][$cleanname] \% expert\n" }
    elsif ($strange ne "")
      { $fntlist .= "\%definefontsynonym[$cleanfont$namesuffix][$cleanname]\n" }
    else
      { $fntlist .= "\\definefontsynonym[$cleanfont$namesuffix][$usename][encoding=$encoding]\n" }
    next unless $tex ;
    if (($strange eq "expert")&&($expert))
      { $texlist .= "\\ShowFont[$cleanfont$namesuffix][$cleanname]\n" }
    elsif ($strange ne "")
      { $texlist .= "\%ShowFont[$cleanfont$namesuffix][$cleanname]\n" }
    else
      { $texlist .= "\\ShowFont[$cleanfont$namesuffix][$usename][$encoding]\n" } }

if ($map)
  { report ("updating map file : $mapfile") ;
    while ($mapdata =~ s/\n\n+/\n/mois) {} ;
    $mapdata =~ s/^\s*//gmois ;
    print MAP $mapdata }

if ($tex)
  { $pdfpath =~ s/\\/\//go ;
    $savedoptions =~ s/^\s+//gmois ; $savedoptions =~ s/\s+$//gmois ;
    $fntlist      =~ s/^\s+//gmois ; $fntlist      =~ s/\s+$//gmois ;
    $maplist      =~ s/^\s+//gmois ; $maplist      =~ s/\s+$//gmois ;
    print TEX "$texlist" ;
    print TEX "\n" ;
    print TEX "\\setupheadertexts[\\tttf example definitions]\n" ;
    print TEX "\n" ;
    print TEX "\\starttyping\n" ;
    print TEX "texfont $savedoptions\n" ;
    print TEX "\\stoptyping\n" ;
    print TEX "\n" ;
    print TEX "\\starttyping\n" ;
    print TEX "$pdfpath/$mapfile\n" ;
    print TEX "\\stoptyping\n" ;
    print TEX "\n" ;
    print TEX "\\starttyping\n" ;
    print TEX "$fntlist\n" ;
    print TEX "\\stoptyping\n" ;
    print TEX "\n" ;
    print TEX "\\page\n" ;
    print TEX "\n" ;
    print TEX "\\setupheadertexts[\\tttf $mapfile]\n" ;
    print TEX "\n" ;
    print TEX "\\starttyping\n" ;
    print TEX "$maplist\n" ;
    print TEX "\\stoptyping\n" ;
    print TEX "\n" ;
    print TEX "\\stoptext\n" }

if ($map) { close (MAP) }
if ($tex) { close (TEX) }

# unlink "$pdfpath/$mapfile" ; # can be same

copy ($mapfile,"$pdfpath/$mapfile") ;

print "\n" ; report ("generating : ls-r databases") ;

# Refresh database.

print "\n" ; system ("mktexlsr $fontroot") ; print "\n" ;

# Process the test file.

if ($show) { system ("texexec --once --silent $texfile") }

@files = validglob("$identifier.*") ;

foreach my $file (@files)
  { unless ($file =~ /(tex|pdf|log|mp|tmp)$/io) { unlink $file } }

exit ;
