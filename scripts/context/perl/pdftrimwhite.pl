eval '(exit $?0)' && eval 'exec perl -S $0 ${1+"$@"}' && eval 'exec perl -S $0 $argv:q'
        if 0;

#D \module
#D   [       file=pdftrimwhite.pl,
#D        version=2000.07.13,
#D          title=PDF postprocessing,
#D       subtitle=cropping whitespace from pdf files,
#D         author=Hans Hagen,
#D           date=\currentdate,
#D      copyright=PRAGMA ADE]

#C This module is part of the \CONTEXT\ macro||package and is
#C therefore copyrighted by \PRAGMA. See readme.pdf for
#C details.

#D This script can be used to crop margins that contain
#D useless information from a \PDF\ image. It does so by:
#D
#D \startitemize[packed,n]
#D \som  cropping the image into an alternative file
#D \som  determining the boundingbox of the alternative
#D \som  cropping the image into a resulting file
#D \stoppacked
#D
#D In the process, some checks are carried out. Step~1 is
#D taken care of by \PDFTEX, step~2 by \GHOSTSCRIPT, using a
#D file generated by \PDFTOPS, and \PDFTEX\ is responsible
#D for step~3.
#D
#D \startuseMPgraphic{original}
#D   numeric n ; n = 1cm ;
#D   path p ; p := fullsquare xyscaled (8n,12n) ;
#D   path q ; q := fullsquare xyscaled (2n,3n) shifted (n,n) ;
#D   path r ; r := ((0,0)--(3n,0)) shifted (0, 5.5n) ;
#D   path s ; s := ((0,0)--(3n,0)) shifted (0,-5.5n) ;
#D   path t ; t := (-2n,-4n) ;
#D   path u ; u := p enlarged -.75n ;
#D   path v ; v := p enlarged (-1.75n,-2n) shifted (n,1.25n) ;
#D   path w ; w := q enlarged .25n ;
#D   fill p                               withcolor .7white ;
#D   fill q                               withcolor .7green ;
#D   draw r withpen pencircle scaled .25n withcolor .7green ;
#D   draw s withpen pencircle scaled .25n withcolor .7green ;
#D   draw t withpen pencircle scaled .50n withcolor .7green ;
#D   draw u withpen pencircle scaled .10n withcolor   white ;
#D   draw v withpen pencircle scaled .10n withcolor .7red   ;
#D   draw w withpen pencircle scaled .10n ;
#D   verbatimtex \tttf \setupframed[frame=off,align=left] etex ;
#D   label    (btex \framed{crap}       etex, center   r) ;
#D   label    (btex \framed{crap}       etex, center   s) ;
#D   label    (btex \framed{crap}       etex, center   t) ;
#D   label    (btex \framed{graphic}    etex, center   q) ;
#D   label.urt(btex \framed{page}       etex, llcorner p) ;
#D   label.urt(btex \framed{crop}       etex, llcorner u) ;
#D   label.lft(btex \framed{leftcrop\\
#D                          rightcrop\\
#D                          topcrop\\
#D                          bottomcrop} etex, .5[ulcorner v,llcorner v]) ;
#D   label.bot(btex \framed{offset}     etex, .5[llcorner w,lrcorner w]) ;
#D \stopuseMPgraphic
#D
#D \placefigure
#D   [here][fig:cropcrap]
#D   {Crops and offsets.}
#D   {\useMPgraphic{original}}
#D
#D The \TEX\ part has two alternatives, one using \CONTEXT, and
#D another using plain \TEX. The \CONTEXT\ method is slower but
#D can be extended more easily.
#D
#D The script is executed as follows:
#D
#D \starttyping
#D cropcrap <original> [<result>] [<switches>]
#D \stoptyping
#D
#D The next call crops \type {test.pdf} to its natural
#D boundingbox.
#D
#D \starttyping
#D cropcrap test
#D \stoptyping
#D
#D If the file has some crap at the bottom, you can say:
#D
#D \starttyping
#D cropcrap test --bottomcrop=2cm
#D \stoptyping
#D
#D This clips 2cm from the bottom. You can clip on all sides
#D individually, in combination or at once, like in:
#D
#D \starttyping
#D cropcrap test --bottomcrop=2cm --crop=1cm
#D \stoptyping
#D
#D The final result is a tightly cropped image. In order to get
#D a 5mm margin around this image, you can say:
#D
#D \starttyping
#D cropcrap test --bottomcrop=2cm --offset=5mm
#D \stoptyping
#D
#D By default, the script intercepts logging messages and
#D writes them to a logfile with the same name as the
#D resulting image and the prefix \type {log}. If no name is
#D given, the name \type {cropcrap} is used for all resulting
#D files.
#D
#D By default, \CONTEXT\ is used. When installed properly, you
#D can also use plain \TEX, by adding a switch \type
#D {--plain}. Partial switched are accepted, so the next call
#D is valid:
#D
#D \starttyping
#D cropcrap test result --bot=2cm --off=5mm --plain
#D \stoptyping
#D
#D The current implementation uses an intermediate \POSTSCRIPT\
#D file. This may change as \GHOSTSCRIPT\ gets more clever with
#D \PDF\ files.
#D
#D In \in {figure} [fig:cropcrap] the green rectangle is the
#D picture we want to keep. Around this picture, we want a
#D margin, represented by the black rectangle, and specified by
#D \type {--offset}. The white rectangle is the cropbox
#D defined by \type {--crop}. That way we get rid of header
#D and footerlines. The red rectangle results from an
#D additional \type {--leftcrop} and \type {-bottomcrop} and
#D takes care of some content, as represented by the green
#D dot.
#D
#D The \type {--verbose} switch can be used to disable the
#D interception of log messages.

#D We load a few \PERL\ modules \unknown\

use Config ;
use Getopt::Long ;

use strict ;

#D \unknown\ and initialize them.

Getopt::Long::Configure
  ("auto_abbrev",
   "ignore_case",
   "pass_through") ;

#D Before fetching the switches, we initialize the
#D variables.

my $Crop       = "0cm" ;

my $LeftCrop   = "0cm" ;
my $RightCrop  = "0cm" ;
my $TopCrop    = "0cm" ;
my $BottomCrop = "0cm" ;

my $Offset     = "0cm" ;

my $GSbin      = "" ;
my $Verbose    = 0 ;
my $Help       = 0 ;
my $UsePlain   = 0 ;

my $Page       = 1 ;

#D On \MSWINDOWS\ and \UNIX\ the following defaults, combined
#D with the check later, should work out okay.

my $pdfps = "pdftops" ;
my $gs    = "gs" ;

my $thisisunix  = $Config{'osname'} !~ /dos|mswin/i ;

#D When no resulting file is given, we use \type {cropcrap}
#D as name (checked later).

my $figurefile = "" ;
my $resultfile = "" ;
my $tempfile   = "" ;

my $programname = "cropcrap" ;

#D Messages are temporarily saved and written to a log file
#D afterwards.

my $results = "" ;
my $pipe    = "" ;
my $result  = "" ;

#D Unfortunately we need this information, first since
#D \PDFTOPS\ does not honor the cropbox, and second because
#D the vertical coordinated are swapped.

my $pwidth   = 597 ;
my $pheight  = 847 ;
my $hoffset  =   0 ;
my $voffset  =   0 ;

#D A few more variables.

my $width = my $height = my $llx = my $lly = my $urx = my $ury = 0 ;

#D Here are the switches we accept. The \type {--gsbin} switch
#D is a bonus one, and the \type {--help} switch comes
#D naturally.

&GetOptions
  ( "leftcrop=s"   => \$LeftCrop  ,
    "rightcrop=s"  => \$RightCrop ,
    "topcrop=s"    => \$TopCrop   ,
    "bottomcrop=s" => \$BottomCrop,
    "crop=s"       => \$Crop      ,
    "offset=s"     => \$Offset    ,
    "verbose"      => \$Verbose   ,
    "gsbin=s"      => \$GSbin     ,
    "plain"        => \$UsePlain  ,
    "page=i"       => \$Page      ,
    "help"         => \$Help      ) ;

#D If asked for, or if no file is given, we provide some
#D help information.

sub PrintHelp
  { print "This is PdfTrimWhite\n\n" .
          "usage:\n\n" .
          "cropcrap [switches] filename result\n\n" .
          "switches:\n\n" .
          "--crop=<dimen>\n" .
          "--offset=<dimen>\n" .
          "--leftcrop=<dimen>\n" .
          "--rightcrop=<dimen>\n" .
          "--topcrop=<dimen>\n" .
          "--bottomcrop=<dimen>\n" .
          "--gsbin=<string>\n" .
          "--page=<number>\n" .
          "--plain\n" .
          "--verbose\n" }

#D The preparations:

sub GetItRight
  { if ($Help)
      { PrintHelp() ; exit }
    $figurefile = $ARGV[0] ; $figurefile =~ s/\.pdf$//oi ;
    $resultfile = $ARGV[1] ; $resultfile =~ s/\.pdf$//oi ;
    $tempfile = "pdftrimwhite-$resultfile" ;
    if ($figurefile eq '')
      { PrintHelp() ; exit }
    unless ($thisisunix)
      { $gs = "gswin32c" }
    if ($GSbin ne '')
      { $gs = $GSbin }
    unless (-e "$figurefile.pdf")
      { print "Something is terribly wrong: no file found\n" ;
        exit }
    if (($resultfile eq '')||($resultfile=~/(^\-|\.)/io))
      { $resultfile = $programname }
    $pipe = "2>&1" ;
    if ($thisisunix)
      { $pipe = "2>&1" } }

#D Something common.

sub SavePageData
  { return "% saving page data
\\immediate\\openout\\scratchwrite=$figurefile.tmp
\\immediate\\write\\scratchwrite
   {\\HOffsetBP\\space\\VOffsetBP\\space
    \\FigureWidthBP\\space\\FigureHeightBP}
\\immediate\\closeout\\scratchwrite\n" }

sub MakePageConTeXt
  { return "% the real work
\\definepapersize
  [Crap]
  [width=\\FigureWidth,
   height=\\FigureHeight]
\\setuppapersize
  [Crap][Crap]
\\setuplayout
  [topspace=0cm,backspace=0pt,
   height=middle,width=middle,
   header=0pt,footer=0pt]
\\starttext
  \\startstandardmakeup
    \\clip
      [voffset=\\VOffset,
       hoffset=\\HOffset,
       width=\\FigureWidth,
       height=\\FigureHeight]
      {\\externalfigure[$figurefile.pdf][page=$Page]\\hss}
  \\stopstandardmakeup
\\stoptext\n" }

sub MakePagePlainTeX
  { return "% the real work
\\output{}
\\hoffset=-1in
\\voffset=\\hoffset
\\pdfpageheight=\\FigureHeight
\\pdfpagewidth=\\FigureWidth
\\vbox to \\pdfpageheight
  {\\offinterlineskip
   \\vskip-\\VOffset
   \\hbox to \\pdfpagewidth{\\hskip-\\HOffset\\box0\\hss}
   \\vss}
\\end\n" }

sub CalculateClip
  { return "% some calculations
\\dimen0=\\figurewidth
\\dimen2=\\figureheight
\\dimen4=$Crop
\\dimen6=$Crop
\\advance\\dimen4 by $LeftCrop
\\advance\\dimen6 by $TopCrop
\\advance\\dimen0 by -\\dimen4
\\advance\\dimen0 by -$Crop
\\advance\\dimen0 by -$RightCrop
\\advance\\dimen2 by -\\dimen6
\\advance\\dimen2 by -$Crop
\\advance\\dimen2 by -$BottomCrop
\\edef\\FigureWidth {\\the\\dimen0}
\\edef\\FigureHeight{\\the\\dimen2}
\\edef\\HOffset     {\\the\\dimen4}
\\edef\\VOffset     {\\the\\dimen6}
\\ScaledPointsToWholeBigPoints{\\number\\dimen0}\\FigureWidthBP
\\ScaledPointsToWholeBigPoints{\\number\\dimen2}\\FigureHeightBP
\\ScaledPointsToWholeBigPoints{\\number\\dimen4}\\HOffsetBP
\\ScaledPointsToWholeBigPoints{\\number\\dimen6}\\VOffsetBP\n" }

sub RecalculateClip
  { return "% some calculations
\\dimen0=${width}bp
\\dimen2=${height}bp
\\dimen4=${hoffset}bp
\\dimen6=${pheight}bp
\\advance\\dimen0 by  $Offset
\\advance\\dimen0 by  $Offset
\\advance\\dimen2 by  $Offset
\\advance\\dimen2 by  $Offset
\\advance\\dimen4 by  ${llx}bp
\\advance\\dimen4 by -$Offset
\\advance\\dimen6 by -${lly}bp
\\advance\\dimen6 by  $Offset
\\advance\\dimen6 by -\\dimen2
\\advance\\dimen6 by  $TopCrop
\\edef\\FigureWidth {\\the\\dimen0}
\\edef\\FigureHeight{\\the\\dimen2}
\\edef\\HOffset     {\\the\\dimen4}
\\edef\\VOffset     {\\the\\dimen6}\n" }

#D The previous scripts could be more sparse, but for the
#D moment we prefer readability. Both scripts save some
#D information in temporary file. We choose between them with
#D the following sub routine.

#D The first pass:

sub PrepareConTeXt
  { return "% interface=en
\\setupoutput[pdftex]
\\getfiguredimensions[$figurefile.pdf][page=$Page]\n" }

sub PreparePlainTeX
  { return "% plain tex alternative, needs recent supp-mis
\\input supp-mis
\\pdfoutput=1
\\newdimen\\figurewidth
\\newdimen\\figureheight
\\setbox0=\\hbox
   {\\immediate\\pdfximage page $Page {$figurefile.pdf}\\pdfrefximage\\pdflastximage}
\\figurewidth=\\wd0
\\figureheight=\\ht0\n" }

sub PrepareFirstPass
  { open (TEX, ">$tempfile.tex") ;
    if ($UsePlain)
      { print TEX
          PreparePlainTeX  .
          CalculateClip    .
          SavePageData     .
          MakePagePlainTeX }
    else
      { print TEX
          PrepareConTeXt  .
          CalculateClip   .
          SavePageData    .
          MakePageConTeXt }
    close TEX }

#D The second pass looks much like the first one, but this
#D time we don't save information, use the natural
#D boundingbox, and provide the offset.

sub SetupConTeXt
  { return "% interface=en
\\setupoutput[pdftex]\n" }

sub SetupPlainTeX
  { return "% plain tex alternative
\\pdfoutput=1
\\setbox0=\\hbox
  {\\immediate\\pdfximage page $Page {$figurefile.pdf}\\pdfrefximage\\pdflastximage}\n" }

sub PrepareSecondPass
  { open (TEX, ">$tempfile.tex") ;
    if ($UsePlain)
      { print TEX
          SetupPlainTeX    .
          RecalculateClip  .
          MakePagePlainTeX }
    else
      { print TEX
          SetupConTeXt    .
          RecalculateClip .
          MakePageConTeXt }
    close TEX }

#D The information we save in the first pass, is loaded here.

sub FetchPaperSize
  { open (TMP,"$figurefile.tmp") ;
    while (<TMP>)
      { chomp ;
        if (/^(\d+) (\d+) (\d+) (\d+) *$/oi)
          { $hoffset = $1 ;
            $voffset = $2 ;
            $pwidth  = $3 ;
            $pheight = $4 ;
            last } }
    close (TMP) }

#D Here we try to find the natural boundingbox. We need to
#D pick up the page dimensions here.

sub RunTeX
  { if ($UsePlain)
      { $result = `pdftex -prog=pdftex -fmt=plain -int=batchmode $tempfile` }
    else
      { $result = `texexec --batch --once --purge $tempfile` }
    print $result if $Verbose ; $results .= "$result\n" }

sub FindBoundingBox
  { $result = `$gs -sDEVICE=bbox -dNOPAUSE -dBATCH $tempfile.pdf $pipe` ;
    print $result if $Verbose ; $results .= "$result\n" }

sub IdentifyCropBox
  { RunTeX() ;
    FetchPaperSize () ;
    FindBoundingBox() }

#D Just to be sure, we check if there is some image data, so
#D that we can retry if something went wrong. Unfortunately we cannot
#D safely check on a high res boundingbox.

my $digits = '([\-\d\.]+)' ;

sub ValidatedCropBox
  { if ($result =~ /BoundingBox:\s*$digits\s+$digits\s+$digits\s+$digits\s*/mois)
      { $llx = $1 ; $lly = $2 ; $urx = $3 ; $ury = $4 }
    else
      { print "Something is terribly wrong: no boundingbox:\n$result\n" ; exit }
    $width  = abs($urx - $llx) ;
    $height = abs($ury - $lly) ;
    if ($width&&$height)
      { return 1 }
    else
      { unless ($width)
          { print "Something seems wrong: no width\n" ;
            $LeftCrop = "0cm" ; $RightCrop  = "0cm" ; $Crop = "0cm" }
        unless ($height)
          { print "Something seems wrong: no height\n" ;
            $TopCrop  = "0cm" ; $BottomCrop = "0cm" ; $Crop = "0cm" }
        return 0 } }

#D This is the main cropping routine.

sub FixCropBox
  { RunTeX() }

#D For error tracing we save the log information in a file.

sub RenameResult
  { unlink "$resultfile.pdf" ;
    rename "$tempfile.pdf", "$resultfile.pdf" }

sub SaveLogInfo
  { open (LOG, ">$resultfile.log") ;
    print LOG $results ;
    close (LOG) }

#D We remove all temporary files.

sub CleanUp
  { unless ($Verbose)
      { unlink "$tempfile.tex" ;
        unlink "$tempfile.tuo" ;
        unlink "$tempfile.tui" ;
        unlink "$figurefile.tmp" } }

#D Here it all comes together.

GetItRight() ;

PrepareFirstPass() ;

IdentifyCropBox () ;

unless (ValidatedCropBox())
  { PrepareFirstPass() ;
    IdentifyCropBox () }

if (ValidatedCropBox())
  { PrepareSecondPass() ;
    FixCropBox() }

RenameResult() ;
SaveLogInfo() ;

CleanUp () ;