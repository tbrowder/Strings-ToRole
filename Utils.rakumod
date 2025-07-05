unit module Font::Utils;

use OO::Monitors;

use Font::FreeType;
use Font::FreeType::SizeMetrics;
use Font::FreeType::Glyph;
use Font::FreeType::Raw::Defs;

use Compress::PDF;
use PDF::API6;
use PDF::Lite;
use PDF::Font::Loader :load-font, :find-font;
use PDF::Lite;
use PDF::Content;
use PDF::Content::Text::Box;

use Font::Utils::FaceFreeType;
use Font::Utils::Misc;
use Font::Utils::Subs;
use Font::Utils::Classes;

our %loaded-fonts is export;
our $HOME is export = 0;
# |= create-user-font-list-file
our $user-font-list is export;
# |== create-user-fonts-hash $user-font-list
our %user-fonts     is export; # key => basename, path
constant $nfonts = 63;         # max number of fonts to collect in Build
BEGIN {
    if %*ENV<HOME>:exists {
        $HOME = %*ENV<HOME>;
    }
    else {
        die "FATAL: The environment variable HOME is not defined";
    }
    if not $HOME.IO.d {
        die qq:to/HERE/;
        FATAL: \$HOME directory '$HOME' is not usable.
        HERE
    }
    my $fdir = "$HOME/.Font-Utils";
    mkdir $fdir;
    $user-font-list = "$HOME/.Font-Utils/font-files.list";
}

INIT {
    if not $user-font-list.IO.r {
        create-user-font-list-file;
    }
    create-user-fonts-hash $user-font-list;

}

=begin comment
# freefont locations by OS
my $Ld = "/usr/share/fonts/opentype/freefont";
my $Md = "/opt/homebrew/Caskroom/font-freefont/20120503/freefont-20120503";
my $Wd = "/usr/share/fonts/opentype/freefont";
=end comment

use MacOS::NativeLib "*";
use QueryOS;
use Font::FreeType;
use Font::FreeType::Glyph;
use Font::FreeType::SizeMetrics;
use File::Find;
use Text::Utils :strip-comment;
use Bin::Utils;
use YAMLish;
use PDF::Lite;
use PDF::API6;
use PDF::Content::Color :ColorName, :color;
use PDF::Content::XObject;
use PDF::Tags;
use PDF::Content::Text::Box;
use Compress::PDF;

use Font::Utils::FaceFreeType;

=begin comment
#=========================================================
# important subset defs (see them tested in t/9-hex-types.t)
#=========================================================
# A single token: no whitespace allowed.  Ultimately, all HexStrRange
# objects will be converted to a list of HexStr objects.
subset HexStr of Str is export where { $_ ~~
    /^
        <[0..9a..fA..F]>+
    $/
}
# A single token: no whitespace allowed.
subset HexStrRange of Str is export where { $_ ~~
    /^
        <[0..9a..fA..F]>+ '-' <[0..9a..fA..F]>+
    $/
}
# One or more tokens in a string, demarked by whitespace.  The string
# will be converted to individual HexStrRange and HexStr tokens with
# the .words method.  Then the entire list will be converted to HexStr
# tokens.
subset HexStrRangeWords of Str is export where { $_ ~~
    /^
        \h*  # optional leading whitespace
             # interleaving HexStrRange and HexStr types
             # first instance is required
             [ [<[0..9a..fA..F]>+ '-' <[0..9a..fA..F]>+] | [<[0..9a..fA..F]>+] ]

             # following instances are optional
             [
               \h+ [ [<[0..9a..fA..F]>+ '-' <[0..9a..fA..F]>+] | [<[0..9a..fA..F]>+] ]
             ]?

        \h*  # optional trailing whitespace
    $/
}
#=========================================================
=end comment

# our $user-font-ignores-list is export; # <== create-user-font-ignores-file
# our %user-font-ignores      is export; # <== create-user-font-ignores-hash 
sub create-user-font-ignores-file(
    :$debug,
    ) is export {
    # created only if it doesn't exist, checks otherwise
}
sub create-user-font-ignores-hash(
    :$debug,
    ) is export {
    # always created from the user's list
}

# our $user-font-list is export; # <== create-user-font-list-file
# our %user-fonts     is export; # <== create-user-fonts-hash 
sub create-user-font-list-file(
    :$debug,
    ) is export {

    use paths;

    my @dirs  = </usr/share/fonts /Users ~/Library/Fonts>;
    my ($bname, $dname, $typ);
    # font hashes: type => <basename> = $path:
    my (%otf, %ttf, %pfb);

    for @dirs -> $dir {
        for paths($dir) -> $path {

            # ignore some
            next if $path ~~ /\h/; # no path with spaces
            next if $path ~~ /Fust/; # way too long a name

            if $path ~~ /:i (otf|ttf|pfb) $/ {
                $typ = ~$0;
                $bname = $path.IO.basename;
                #my $nc = $bname.chars;
                #$nbc = $nc if $nc > $nbc;

                if $typ eq 'otf' {
                    %otf{$bname} = $path;
                }
                elsif $typ eq 'ttf' {
                    %ttf{$bname} = $path;
                }
                elsif $typ eq 'pfb' {
                    %pfb{$bname} = $path;
                }
                say "Font file $typ: $path" if $debug;
            }
        }
    }

    # now put them in directory $HOME/.Font-Utils
    my $f = $user-font-list;

    # first put them in a list before getting sizes

    # prioritize freefonts, garamond, and urw-base35
    # and the others in my FF list
    # also put list from ff docs into docs here
    my @order = <
        FreeSerif.otf
        FreeSerifBold.otf
        FreeSerifItalic.otf
        FreeSerifBoldItalic.otf

        FreeSans.otf
        FreeSansBold.otf
        FreeSansOblique.otf
        FreeSansBoldOblique.otf

        FreeMono.otf
        FreeMonoBold.otf
        FreeMonoOblique.otf
        FreeMonoBoldOblique.otf

        EBGaramond08-Italic.otf
        EBGaramond08-Regular.otf
        EBGaramond12-AllSC.otf
        EBGaramond12-Bold.otf
        EBGaramond12-Italic.otf
        EBGaramond12-Regular.otf
        EBGaramondSC08-Regular.otf
        EBGaramondSC12-Regular.otf

        EBGaramond-Initials.otf
        EBGaramond-InitialsF1.otf
        EBGaramond-InitialsF2.otf

        Cantarell-Regular.otf
        Cantarell-Bold.otf
        Cantarell-ExtraBold.otf
        Cantarell-Light.otf
        Cantarell-Thin.otf

        C059-BdIta.otf
        C059-Bold.otf
        C059-Italic.otf
        C059-Roman.otf
        D050000L.otf
        NimbusMonoPS-Regular.otf
        NimbusMonoPS-Bold.otf
        NimbusMonoPS-Italic.otf
        NimbusMonoPS-BoldItalic.otf
        NimbusRoman-Regular.otf
        NimbusRoman-Bold.otf
        NimbusRoman-Italic.otf
        NimbusRoman-BoldItalic.otf
        NimbusSans-Regular.otf
        NimbusSans-Bold.otf
        NimbusSans-Italic.otf
        NimbusSans-BoldItalic.otf
        NimbusSansNarrow-Regular.otf
        NimbusSansNarrow-Bold.otf
        NimbusSansNarrow-Oblique.otf
        NimbusSansNarrow-BoldOblique.otf
        P052-Roman.otf
        P052-Bold.otf
        P052-Italic.otf
        P052-BoldItalic.otf
        StandardSymbolsPS.otf
        URWBookman-Demi.otf
        URWBookman-DemiItalic.otf
        URWBookman-Light.otf
        URWBookman-LightItalic.otf
        URWGothic-Book.otf
        URWGothic-BookOblique.otf
        URWGothic-Demi.otf
        URWGothic-DemiOblique.otf
        Z003-MediumItalic.otf

    >;

    #note "DEBUG: my font list has {@order.elems} files (early exit)"; exit;

    my @full-font-list;

    for @order {
        if %otf{$_}:exists {
            my $b = $_;
            my $p = %otf{$b};
            @full-font-list.push: "$b $p";

            # then delete from the otf collection
            %otf{$_}:delete;
        }
    }

    for %otf.keys.sort {
        my $b = $_;
        my $p = %otf{$b};
        @full-font-list.push: "$b $p";
    }

    for %ttf.keys.sort {
        my $b = $_;
        my $p = %ttf{$b};
        @full-font-list.push: "$b $p";
    }

    for %pfb.keys.sort {
        my $b = $_;
        my $p = %pfb{$b};
        @full-font-list.push: "$b $p";
    }

    # NOW collect basename lengths
    my $nff = 0; # number of fonts found
    my @fonts;
    my $nbc = 0;
    my $nkc = $nfonts.Str.chars;
    for @full-font-list {
        ++$nff;
        last if $nff > $nfonts;

        my $b = $_.words.head;
        my $nc = $b.chars;
        $nbc = $nc if $nc > $nbc;
        @fonts.push: $_;
    }

    # Finally, create the pretty file
    # key basename path
    my $fh = open $user-font-list, :w;
    $fh.say: "# key  basename  path";

    my $nkey = 0;
    for @fonts {
        ++$nkey;
        my $b = $_.words.head;
        my $p = $_.words.tail;
        my $knam = sprintf '%*d', $nkc, $nkey;
        my $bnam = sprintf '%-*s', $nbc, $b;
        $fh.say: "$knam $bnam $p";
    }
    $fh.close;

}
# our $user-font-list is export; # <== create-user-font-list-file
# our %user-fonts     is export; # <== create-user-fonts-hash $user-font-list
sub create-user-fonts-hash(
    $font-file,
    :$debug,
    ) is export {
    # reads user's font list and fills %user-fonts
    for $font-file.IO.lines -> $line is copy {
        $line = strip-comment $line;
        next unless $line ~~ /\S/;
        my @w    = $line.words;
        my $key  = @w.shift;
        my $bnam = @w.shift;
        my $path = @w.shift;
        %user-fonts{$key}<basename> = $bnam;
        %user-fonts{$key}<path>     = $path;
    }
}
#=========================================================


my $o = OS.new;
my $onam = $o.name;

# use list of font file directories of primary
# interest on Debian (and Ubuntu)
our @fdirs is export;
with $onam {
    when /:i deb|ubu / {
        @fdirs = <
            /usr/share/fonts/opentype/freefont
        >;

        #   /usr/share/fonts/opentype/linux-libertine
        #   /usr/share/fonts/opentype/cantarell
    }
    when /:i macos / {
        @fdirs = <
            /opt/homebrew/Caskroom/font-freefont/20120503/freefont-20120503
        >;
    }
    when /:i windows / {
        @fdirs = <
            /usr/share/fonts/opentype/freefont
        >;
    }
    default {
        die "FATAL: Unhandled OS name: '$_'. Please file an issue."
    }
}

sub help() is export {
    print qq:to/HERE/;
    Usage: {$*PROGRAM.basename} <mode> ...font files...

    Provides various programs and routines to aid working with
    fonts. The first argument is the desired operation.
    Remaining arguments are expected to be a set of font files
    or files containing lists of files and directories to
    investigate.

    Optional key=value arguments for the 'sample' mode may be mixed in
    with them. See the README for details.

    The 'sample' mode can take one or more 'key=value' options
    as shown below.

    All of the modes take one of several options depending on the mode
    selected.

    Modes:
      list    - List family and font names in a set of font files
      show    - Show details of a font file
      sample  - Create a PDF document showing samples of
                  a selected font

    Options:
      (src)   - For all modes, select a font file, directory, or
                a key value from the %user-fonts. The action taken
                depends on the mode. All selections fall back
                to using the %user-fonts if necessary.

      m=A4    - A4 media (default: Letter)
      s=X     - Where X is the font size (default: 16)
      b=X     - Any entry will result in showing the glyph's baseline,
                  the glyph's origin, its horizontal-advance, and the
                  previous line's baseline
      ng=X    - Show max of X glyphs per section
      ns=X    - Show first X sections
      sn=X    - Show only section X
      of=X    - Set \$ofil to X

    HERE
    =begin comment
    # NYI
      o=L     - Landscape orientation
      d=X     - Where X is a code selecting what additional information
                  will be displayed on the box
                  reference
    =end comment
    exit;
}
#=======================================================

# modes and options
my $Rlist    = 0;
my $Rshow    = 0;
my $Rsample  = 0;
my $debug    = 0;

sub do-build(
    :$debug,
    :$delete,
    ) is export {
    say "DEBUG: in sub do-build" if $debug;
    my $f = $user-font-list;

    if $delete and $f.IO.r {
        say "DEBUG: unlinking existing font-list" if $debug;
        unlink $f;
    }

    if $f.IO.r {
        # check it
        say "DEBUG: calling check-font-list" if $debug;
        check-font-list :$debug;
    }
    else {
        # create it

        say "DEBUG: calling create-user-font-list-file" if $debug;
        create-user-font-list-file :$debug;
    }
}


sub check-font-list(
    :$debug,
    ) is export {
    say "DEBUG: entering check-font-list" if $debug;
    my $f = $user-font-list;
    for $f.IO.lines -> $line is copy {
        $line = strip-comment $line;
    }

    =begin comment
    my $flist = "font-files.list";
    if $fdir.IO.d {
        # warn and check it
        my $f = "$fdir/$flist";
        my (%k, $k, $b, $p);
        my $errs = 0;
        my $einfo = "";
        for $f.IO.lines -> $line is copy {
            # skip blank lines and comments
            $line = strip-comment $line;
            next unless $f ~~ /\S/;
            my @w = $line.words;
            if not @w.elems == 3 {
            }
            $k = @w.shift;
            $b = @w.shift;
            $p = @w.shift;
        }
    }
    =end comment

}

sub use-args(@args is copy) is export {
    my $mode = @args.shift;

    # also check for xxx = debug
    my @targs = @args;
    @args = [];
    for @targs {
        if $_ ~~ /^ xxx / {
            ++$debug;
            next;
        }
        @args.push: $_;
    }

    with $mode {
        when /^ :i L / {
            ++$Rlist;
        }
        when /^ :i sh / {
            ++$Rshow;
        }
        when /^ :i sa / {
            ++$Rsample;
        }
        default {
            if $mode ~~ /^ :i s/ {
                say "FATAL: Uknown mode '$_'";
                say "  (did you mean 'show' or 'sample'?)";
            }
            else {
                say "FATAL: Uknown mode '$_'";
            }
            exit;
        }
    }

    # remaining args are a mixed bag
    # we must have an arg (file, or dir, or fkey)
    my ($dir, $file, $fkey, $key);   # file or dir

    my %opts;
    for @args {
        when /^ :i (\w+) '=' (\w+) / {
            my $key = ~$0;
            my $val = ~$1;
            # decode later
            %opts{$key} = $val;
        }
        when /^ :i (\S+) / {
            # a possible font key
            # it cannot be zero
            $fkey = ~$0;
            if %user-fonts{$fkey}:exists {
                say "DEBUG: selected font key '$fkey'" if $debug;
                $file = %user-fonts{$fkey}<path>;
                if $debug {
                    say "DEBUG: font file: $file";
                    say "DEBUG exit"; exit;
                }
            }
            else {
                # take the first file in the user's list
                $file = %user-fonts<1><path>;
                ; # ok #say "Listing your fonts...";
            }
        }
        when $_.IO.d {
            say "'$_' is a directory";
            $dir = $_;
        }
        when $_ ~~ /\w/ and $_.IO.r {
            say "'$_' is a file";
            $file = $_;
        }
        default {
            die "FATAL: Uknown option '$_'";
        }
    } # end of arg handling

    if $debug {
        say "DEBUG is selected";
    }

    unless $dir or $file or $fkey {
        say "No file, dir, or fkey was entered.";
        exit;
    }

    # take care of $file or $dir, and %opts
    # if we have a file, it must be a font file

    my @fils;
    my $font-size = 12;
    my $font;

    for @fils {
        next if not $_;
        next if not $_.e;
        say "DEBUG: trying a file '$_'" if $debug;
        $font = load-font :file($_);
        my $o = FaceFreeType.new: :file($_), :$font-size, :$font;
    }

    if $file {
        say "DEBUG: trying a file '$file'" if $debug;
        #my $o = FaceFreeType.new: :$file, :$font-size, :$font;
    }

    if $debug {
        say "DEBUG is on";
    }

    #=====================================================
    if $Rlist {
        # list   - List family and font names in a font directory
        # show   - Show details of a font file
        # sample - Create a PDF document showing samples of
        #            selected fonts in a list of font files

        my @fils;
        if $dir.defined {
            @fils = find :$dir, :type<file>, :name(/'.' [otf|ttf|pfb]/);
        }
        else {
            # get the user's list
            @fils = get-user-font-list;
        }

        my %fam; # keyed by family name => [ files... ]
        my %nam; # keyed by postscript name

        my @fams;
        my $font;
        for @fils {
            say "DEBUG: path = '$_'" if 0 or $debug;
            my $file = $_.IO.absolute;
            $font = load-font :$file;
            my $o      = FaceFreeType.new: :$file, :$font-size, :$font;
            my $pnam   = $o.postscript-name;
            my $anam   = $o.adobe-name;
            my $fam    = $o.family-name;
            if %fam{$fam}:exists {
                %fam{$fam}.push: $file;
            }
            else {
                %fam{$fam} = [];
                %fam{$fam}.push: $file;
                @fams.push: $fam;
            }
            %nam{$pnam} = $_;
        }

        my @nams = %nam.keys.sort;

        say "Font family names and fonts:";
        my $idx = 0;
        for @fams -> $fam {
            my @f = @(%fam{$fam}); #++$idx;
            for @f -> $f {
                my $fil = $f.IO.basename;
                ++$idx;
                say "$idx  $fam   $fil";
            }
        }

        say "End of mode 'list'" if 1;
        exit;
    } # end of $Rlist

    #=====================================================
    if $Rshow {
        # list    - List family and font names in a font directory
        #             input: $dir OR anything else uses user font list
        # show    - Show details of a font file
        #             input: $file
        # sample  - Create a PDF document showing samples of
        #           the selected font
        #             input: $file OR key of user font hash

        if is-font-file $file {
            my $font = load-font :$file;
            my $font-size = 12;
            my $o = FaceFreeType.new: :$font, :$font-size, :$file;
            #$o.show;
        }
        else {
            $file = %user-fonts<1>;
        }

        # use a kludge for now
        show-font-info $file;

        # get a font key
        my $k1 = 1;
        my $k2 = 2;

        # load the font file
        my $f1 = load-font-at-key $k1;
        my $f2 = load-font-at-key $k1;

        say "End of mode 'show'" if 1;
        exit;
    } # end of $Rshow

    if $Rsample {
        # sample  - Create a PDF document showing samples of
        #           the selected font
        #             input: $file OR key of user font hash

        my $fo;
        if is-font-file $file {
            ; # ok $fo = FreeTypeFace.new: :$file;
        }
        else {
            $file = %user-fonts<1>;
            # $fo = FreeTypeFace.new: :$file;
        }

        if $debug {
            say "DEBUG: mode sample, file selected:";
            say "       $file";
        }

        # use a kludge for now
        say "Producing a font sample for file:";
        my $bnam = $file.IO.basename;
        say "          '$bnam'...";

        # exe...
        make-font-sample-doc $file,
            :%opts, :$debug;

        say "End of mode 'sample'" if 1;
        exit;
    } # end of $Rlist

}

sub get-user-font-list(
    :$all,
    :$debug,
    --> List
    ) is export {
    # return list cleaned of comments
    my @lines;
    for $user-font-list.IO.lines -> $line is copy {
        $line = strip-comment $line;
        next unless $line ~~ /\S/;
        unless $all {
            $line = $line.words.tail;
            $line = $line.IO.absolute;
            say "DEBUG: line path = '$line'" if 0 or $debug;
        }
        @lines.push: $line;
    }
    @lines
}

sub load-font-at-key(
    $key,
    :$debug,
    --> PDF::Content::FontObj
    ) is export {
    # Given a key, first see if it has been loaded, if so, return a
    # reference to that object.
    if %loaded-fonts{$key}:exists {
        return %loaded-fonts{$key};
    }
    # not loaded, get the file path from the user's font list
    # the hash may not be populated yet
    if not %user-fonts.elems {
        #die "Tom, fix this";
        # read the user's font list
        create-user-fonts-hash $user-font-list, :$debug;
    }

    my $file = %user-fonts{$key}<path>;
    my $font = load-font :$file;
    %loaded-fonts{$key} = $font;
    $font;
}

sub show-font-info(
    $path,
    :$debug
    ) is export {

    if not $path.IO.r {
        die "FATAL: \$path is not a valid font path";
    }

    my $file = $path; # David's sub REQUIRES a Str for the $filename
    my $font = load-font :$file;
    my $font-size = 12;

    # get a sister FreeTypeFace to gradually take over
    my $o = FaceFreeType.new: :$file, :$font, :$font-size;

    my $face = Font::FreeType.new.face($file);

    say "Path: $file";
    my $bname = $path.IO.basename;

    say "  Basename: ", $bname;
    say "  Family name: ", $face.family-name;
    say "  Style name: ", $_
        with $face.style-name;
    say "  PostScript name: ", $_
        with $face.postscript-name;
    say "  Adobe name: ", $_
        with $o.adobe-name;
    say "  Format: ", $_
        with $face.font-format;

    # properties
    my @properties;
    @properties.push: '  Bold' if $face.is-bold;
    @properties.push: '  Italic' if $face.is-italic;
    say @properties.join: '  ' if @properties;
    @properties = ();
    @properties.push: 'Scalable'    if $face.is-scalable;
    @properties.push: 'Fixed width' if $face.is-fixed-width;
    @properties.push: 'Kerning'     if $face.has-kerning;
    @properties.push: 'Glyph names' ~
                      ($face.has-reliable-glyph-names ?? '' !! ' (unreliable)')
      if $face.has-glyph-names;
    @properties.push: 'SFNT'        if $face.is-sfnt;
    @properties.push: 'Horizontal'  if $face.has-horizontal-metrics;
    @properties.push: 'Vertical'    if $face.has-vertical-metrics;
    with $face.charmap {
        @properties.push: 'enc:' ~ .key.subst(/^FT_ENCODING_/, '').lc
            with .encoding;
    }
    #say @properties.join: '  ' if @properties;
    my $prop = @properties.join(' ');
    say "  $prop";

    say "  Units per em: ", $face.units-per-EM if $face.units-per-EM;
    if $face.is-scalable {
        with $face.bounding-box -> $bb {
            say sprintf('  Global BBox: (%d,%d):(%d,%d)',
                        <x-min y-min x-max y-max>.map({ $bb."$_"() }) );
        }
        say "  Ascent: ", $face.ascender;
        say "  Descent: ", $face.descender;
        say "  Text height: ", $face.height;
    }
    say "  Number of glyphs: ", $face.num-glyphs;
    say "  Number of faces: ", $face.num-faces
      if $face.num-faces > 1;
    if $face.fixed-sizes {
        say "  Fixed sizes:";
        for $face.fixed-sizes -> $size {
            say "    ",
            <size width height x-res y-res>\
                .grep({ $size."$_"(:dpi)})\
                .map({ sprintf "$_ %g", $size."$_"(:dpi) })\
                .join: ", ";
        }
    }
    my $tstr = "Some text";
    my $sz = 12;
    $face.set-char-size($sz);

    my $sw = stringwidth($tstr, :$face, :kern);
    say "  Stringwidth of '$tstr' at font size $sz: $sw points";

    $sz = 24;
    $face.set-char-size($sz);
    $sw = stringwidth($tstr, :$face, :kern);
    say "  Stringwidth of '$tstr' at font size $sz: $sw points";
}

sub stringwidth(
    Str $s,
    :$font-size = 12,
    :$face!,
    :$kern,
    :$debug,
    ) is export {

    # from sub stringwidth demoed in Font::FreeType (but without kern)
    # note PDF::Font::Loader does have a :kern capability with 'text-box'
    #method stringwidth($s, :$font-size = 12, :$kern) {

    my $units-per-EM = $face.units-per-EM;
    my $unscaled = sum $face.for-glyphs($s, {.metrics.hori-advance });
    return $unscaled * $font-size / $units-per-EM;
}

sub get-font-info(
    $path,
    :$debug
    --> FaceFreeType
    ) is export {

    my $file;
    if $path and $path.IO.e {
        $file = $path; #.Str; # David's sub REQUIRES a Str for the $filename
    }
    else {
        $file = %user-fonts{$path};
    }

    my $o = FaceFreeType.new: :$file;
    $o;
}

sub X(
    $font-file,
    :$text is copy,
    :$size,
    :$nglyphs = 0,
    :$width!,      #= max length of a line of text of font F and size S
    :$debug,
    --> Str        #= with line breaks per input params
    ) is export {
}

sub pdf-font-samples(
    # given a list of font files and a text string
    # prints PDF pages in the given font sizes
    @fonts,
    :$text is copy,           #= if not defined, use glyphs in sequence from 100
    :$ngyphs = 0,             #= use a number > 0 to limit num of glyphs shown
    :$size  = 12,
    :$media = 'Letter',
    :$orientation = 'portrait',
    :$margins = 72,
    :$ofil = "font-samples.pdf",
    :$debug,
    ) is export {

    if not $text.defined {
    }

    # start the document
    my $pdf  = PDF::Lite.new;
    if $media.contains( 'let', :i) {
        $pdf.media-box = (0, 0, 8.5*72, 11.0*72);
    }
    else {
        # A4 w x h = 210 mm x 297 mm
        # 25.4 mm per inch
        $pdf.media-box = (0, 0, 210 / 25.4 * 72, 297 / 25.4 * 72);
    }

    my $page;
    my $next-font-index = 0;

    # print the pages(s)
    while $next-font-index < @fonts.elems {
        $page = $pdf.add-page;
        $page.media-box = $pdf.media-box;
        #$next-font-index = make-page $next-font-index, @fonts,
        $next-font-index = make-font-page $next-font-index, @fonts,
           :$page, :$size, :$orientation, :$margins, :$debug;
    }

} # sub pdf-font-samples

sub make-sample-page(
    $text is copy,
    :$font!,
    PDF::Lite::Page :$page!,
    :$text-is-hex,
    :$font-size = 12,
    :$debug,
) is export {
    my @lines = $text.lines;

    # for now assume letter paper in portrait with one-inch margins
    $page.media-box = 0, 0, 8.5*72, 11*72;

    my ($x, $y) = 72, 720;
    my $g = $page.gfx;
    $g.Save;

    if 0 {
        $g.transform: :translate($x, $y);
        ($x, $y) = 0, 0;
    }

    # now we're at upper-left corner of content area
    # define a single box

    if $text-is-hex {
        my $s = "";
        for @lines -> $line {
            say "DEBUG: line: '$line'" if 0 or $debug;
            # each line is a hex word string
            my @w = $line.words;
            if 0 or $debug {
                say "DEBUG: word: '$_'" for @w;
            }

            my @g = HexStrs2GlyphStrs @w;
            if 0 or $debug {
                say "DEBUG: glyph: '$_'" for @g;
            }

            for @g -> $g {
                my $gs = hex2string $g;
                say "DEBUG: gstr: '$gs'" if 0 or $debug;
                $s ~= $gs;
            }
            # add a space between words
            $s ~= " ";
        }
        # print the text
        # text is space separated, and may have newlines for paras
        my @bbox;
        $page.text: {
            .text-position = $x, $y;
            my PDF::Content::Text::Box $tb .= new(
                :text($s), :$font, :$font-size, :height(20),
                :WordSpacing(10)
            );
            @bbox = .print: $tb;
        }
    }
    else {
        # text is space separated, and may have newlines for paras
        $page.text: {
            .font = $font, $font-size;
            .text-position = $x, $y;
            .print: $text;
        }
    }

    =begin comment
    # use a text box
    ($x, $y) = 72, 600;
    #$text = "here we go again";

    $page.text: {
        .text-position = $x, $y;
        #my PDF::Content::Text::Box $tb .= new(
        my PDF::Content::Text::Box $tb .= new(
            :$text, :$font, :$font-size, :height(20),
            :space-width(30)
        );
        #$tb.space-width(30);
        .print: $tb;
    }
    =end comment

    $g.Restore;
}


# TODO put this sub in dev/
#sub make-page(
sub make-font-page(
    $next-font-index is copy,
    @fonts,
    PDF::Lite::Page :$page!,
    :$size,
    :$orientation,
    :$margins,
    :$debug,
    --> UInt
) is export {
    # we must keep track of how many fonts were shown
    # on the page and return a suitable reference

    # some references
    my ($ulx, $uly, $pwidth, $pheight);

    =begin comment
    my $up = $font.underlne-position;
    my $ut = $font.underlne-thickness;
    note "Underline position:  $up";
    note "Underline thickness: $ut";
    =end comment

    # portrait is default
    # use the page media-box
    $pwidth  = $page.media-box[2];
    $pheight = $page.media-box[3];
    if $orientation.contains('land', :i) {
        # need a transformation
        die "FATAL: Tom, fix this";
        return
        $pwidth  = $page.media-box[3];
        $pheight = $page.media-box[2];
    }
    $ulx = 0;
    $uly = $pheight;

    my (@bbox, @position);

=begin comment
    $page.graphics: {
        .Save;
        .transform: :translate($page.media-box[2], $page.media-box[1]);
        .transform: :rotate(90 * pi/180); # left (ccw) 90 degrees

        # is this right? yes, the media-box values haven't changed,
        # just its orientation with the transformations
        my $w = $page.media-box[3] - $page.media-box[1];
        my $h = $page.media-box[2] - $page.media-box[0];
        $cx = $w * 0.5;

        # get the font's values from FontFactory
        my ($leading, $height, $dh);
        $leading = $height = $dh = $sm.height; #1.3 * $font-size;

        # use 1-inch margins left and right, 1/2-in top and bottom
        # left
        my $Lx = 0 + 72;
        my $x = $Lx;
        # top baseline
        my $Ty = $h - 36 - $dh; # should be adjusted for leading for the font/size
        my $y = $Ty;

        # start at the top left and work down by leading
        #@position = [$lx, $by];
        #my @bbox = .print: "Fourth page (with transformation and rotation)", :@position, :$font,
        #              :align<center>, :valign<center>;

        # print a page title
        my $ptitle = "FontFactory Language Samples for Font: $font-name";
        @position = [$cx, $y];
        @bbox = .print: $ptitle, :@position,
                       :font($title-font), :font-size(16), :align<center>, :kern;
        my $pn = "Page $curr-page of $npages"; # upper-right, right-justified
        @position = [$rx, $y];
        @bbox = .print: $pn, :@position,
                       :font($pn-font), :font-size(10), :align<right>, :kern;

        if $debug {
            say "DEBUG: \@bbox with :align\<center>: {@bbox.raku}";
        }

#        =begin comment
#        # TODO file bug report: @bbox does NOT recognize results of
#        #   :align (and probably :valign)
#        # y positions are correct, must adjust x left by 1/2 width
#        .MoveTo(@bbox[0], @bbox[1]);
#        .LineTo(@bbox[2], @bbox[1]);
#        =end comment
        my $bwidth = @bbox[2] - @bbox[0];
        my $bxL = @bbox[0] - 0.5 * $bwidth;
        my $bxR = $bxL + $bwidth;

#        =begin comment
#        # wait until underline can be centered easily
#
#        # underline the title
#        # underline thickness, from docfont
#        my $ut = $sm.underline-thickness; # 0.703125;
#        # underline position, from docfont
#        my $up = $sm.underline-position; # -0.664064;
#        .Save;
#        .SetStrokeGray(0);
#        .SetLineWidth($ut);
#        # y positions are correct, must adjust x left by 1/2 width
#        .MoveTo($bxL, $y + $up);
#        .LineTo($bxR, $y + $up);
#        .CloseStroke;
#        .Restore;
#        =end comment

        # show the text font value
        $y -= 2* $dh;

        $y -= 2* $dh;

        for %h.keys.sort -> $k {
            my $country-code = $k.uc;
            my $lang = %h{$k}<lang>;
            my $text = %h{$k}<text>;

#            =begin comment
#            @position = [$x, $y];
#            my $words = qq:to/HERE/;
#            -------------------------
#              Country code: {$k.uc}
#                  Language: $lang
#                  Text:     $text
#            -------------------------
#            =end comment

            # print the dashed in one piece
            my $dline = "-------------------------";
            @bbox = .print: $dline, :position[$x, $y], :$font, :$font-size,
                            :align<left>, :kern; #, default: :valign<bottom>;

            # use the @bbox for vertical adjustment [1, 3];
            $y -= @bbox[3] - @bbox[1];

            #  Country code / Language: {$k.uc} / German
            @bbox = .print: "{$k.uc} - Language: $lang", :position[$x, $y],
                    :$font, :$font-size, :align<left>, :!kern;

            # use the @bbox for vertical adjustment [1, 3];
            $y -= @bbox[3] - @bbox[1];

            # print the line data in two pieces
            #     Text:     $text
            @bbox = .print: "Text: $text", :position[$x, $y],
                    :$font, :$font-size, :align<left>, :kern;

            # use the @bbox for vertical adjustment [1, 3];
            $y -= @bbox[3] - @bbox[1];
        }
        # add a closing dashed line
        # print the dashed in one piece
        my $dline = "-------------------------";
        @bbox = .print: $dline, :position[$x, $y], :$font, :$font-size,
                :align<left>, :kern; #, default: :valign<bottom>;

        #=== end of all data to be printed on this page
        .Restore; # end of all data to be printed on this page
    }
=end comment

    $next-font-index;

} # sub make-page

sub rescale(
    $font,
    :$debug,
    --> Numeric
    ) is export {
    # Given a font object with its size setting (.size) and a string of text you
    # want to be an actual height X, returns the calculated setting
    # size to achieve that top bearing.
    # TODO fill in
} # sub rescale(

sub write-line(
    $page,
    :$font!,  # DocFont object
    :$text!,
    :$x!, :$y!,
    :$align = "left", # left, right, center
    :$valign = "baseline", # baseline, top, bottom
    :$debug,
) is export {

    $page.text: -> $txt {
        $txt.font = $font.font, $font.size;
        $txt.text-position = [$x, $y];
        # collect bounding box info:
        my ($x0, $y0, $x1, $y1) = $txt.say: $text, :$align, :kern;
        # bearings from baseline origin:
        my $tb = $y1 - $y;
        my $bb = $y0 - $y;
        my $lb = $x0 - $x;
	my $rb = $x1 - $x;
        my $width  = $rb - $lb;
        my $height = $tb - $bb;
        if $debug {
            say "bbox: llx, lly, urx, ury = $x0, $y0, $x1, $y1";
            say " width, height = $width, $height";
            say " lb, rb, tb, bb = $lb, $rb, $tb, $bb";
        }
    }
} # sub write-line

=begin comment
sub DecStrRangeWords2HexStrs(
    DecStrRangeWords @words,
    :$debug,
     --> List
) is export {
    # Given a list of decimal or decimal-range code points, convert
    # them to a list of GlypStr strings.
}
=end comment

sub HexStrs2GlyphStrs(
    @words,
    :$ng-to-show,
    :$debug,
    --> List
    ) is export {
    # Given a list of hexadecimal or hexadecimal-range code points,
    # convert them to a list of GlypStr strings.
    my @c;

    my $ng = 0;
    WORD: for @words -> $w is copy {
        $w = $w.Str;
        if $debug {
            say "DEBUG: input hex range word: '$w'" if $w ~~ /'-'/;
            say "DEBUG: input hex range word: '$w'" if $debug;
        }
        if $w ~~ /^:i (<[0..9A..Fa..f]>+) '-' (<[0..9A..Fa..f]>+) $/ {
            my $a = ~$0;
            my $b = ~$1;
            # it's a range, careful, have to convert the range to decimal
            # convert from hex to decimal
            my $aa = parse-base "$a", 16;
            my $bb = parse-base "$b", 16;
            say "DEBUG: range hex: '$a' .. '$b'" if $debug;
            say "DEBUG: range dec: '$aa' .. '$bb'" if $debug;
            my @tchars = [];
            for $aa..$bb -> $d {
                # get its hex str
                #my HexStr $c = dec2hex $d;
                my $c = dec2hex $d;
                say "DEBUG: char decimal value '$d', hex value '$c'" if $debug;
                @tchars.push: $c;
            }
            # now count the chars
            for @tchars -> $c {
                ++$ng;
                say "DEBUG: its hex value: '$c'" if $debug;
                @c.push: $c;
                #last WORD unless $ng < $ng-to-show;
            }

        }
        elsif $w ~~ HexStr {
            ++$ng;
            say "DEBUG: its hex value: '$w'" if $debug;
            @c.push: $w;
            #last WORD unless $ng < $ng-to-show;
        }
        else {
            say "DEBUG:   its hex value: '$w'" if $debug;
            die "FATAL: word '$w' is not a HexStr";
        }
    }

    =begin comment
    if @c.elems > $ng-to-show {
        @c = @c[0..^$ng-to-show];
    }
    =end comment
    @c
}

sub find-local-font is export {
    # use the installed file set
    my $f = %user-fonts<1>;
    $f;
}

sub draw-rectangle-clip(
    :$llx!,
    :$lly!,
    :$width!,
    :$height!,
    :$page!,
    :$stroke-color = (color Black),
    :$fill-color   = (color White),
    :$linewidth = 0,
    :$fill is copy,
    :$stroke is copy,
    :$clip is copy,
    :$debug,
    ) is export {

    $fill   = 0 if not $fill.defined;
    $stroke = 0 if not $stroke.defined;
    $clip   = 0 if not $clip.defined;
    # what if none are defined?
    if $clip {
        # MUST NOT TRANSFORM OR TRANSLATE
        ($fill, $stroke) = 0, 0;
    }
    else {
        # make stroke the default
        $stroke = 1 if not ($fill or $stroke);
    }
    if $debug {
        say "   Drawing a circle...";
        if $fill {
            say "     Filling with color $fill-color...";
        }
        if $stroke {
            say "     Stroking with color $stroke-color...";
        }
        if $clip {
            say "     Clipping the circle";
        }
        else {
            say "     NOT clipping the circle";
        }
    }
    my $g = $page.gfx;
    $g.Save if not $clip; # CRITICAL
    # NO translation
    if not $clip {
        $g.SetLineWidth: $linewidth;
        $g.StrokeColor = $stroke-color;
        $g.FillColor   = $fill-color;
    }
    # draw the path
    $g.MoveTo: $llx, $lly;
    $g.LineTo: $llx+$width, $lly;
    $g.LineTo: $llx+$width, $lly+$height;
    $g.LineTo: $llx       , $lly+$height;
    $g.ClosePath;
    if not $clip {
        if $fill and $stroke {
            $g.FillStroke;
        }
        elsif $fill {
            $g.Fill;
        }
        elsif $stroke {
            $g.Stroke;
        }
        else {
            die "FATAL: Unknown drawing status";
        }
        $g.Restore;
    }
    else {
        $g.Clip;
        $g.EndPath;
    }

} # sub draw-rectangle-clip

sub find-local-font-file(
    :$debug,
    ) is export {

    # Find the first installed font file in the
    # local file system for and example use.
    use paths;
    my $font-file = 0;
    my @dirs  = </usr/share/fonts /Users ~/Library/Fonts>;
    for @dirs -> $dir {
        for paths($dir) -> $path {
            # take the first of the set of known types handled by PDF
            # libraries (in order of preference)
            #if $path ~~ /:i otf|ttf|woff|pfb $/ {
            if $path ~~ /:i otf|ttf|pfb $/ {
                $font-file = $path;
                say "Font file: $path" if $debug;
                last;
            }
        }
    }
    if not $font-file {
        say "WARNING: No suitable font file was found."
    }
    $font-file
}

sub text-box(
    $text = "",
    :$font!, # fontobj from PDF::Font::Loader
    :$font-size = 12,
    # optional args with defaults
    :$squish = False,
    :$kern = True,
    :$align = <left>, # center, right, justify, start, end
    :$width = 8.5*72,  # default is Letter width in portrait orientation
    :$indent = 0;
    # optional args that depend on definedness
    :$verbatim, #  = False,
    :$height, # = 11*72,  # default is Letter height in portrait orientation
    :$valign, #  = <bottom>, # top, center, bottom
    :$bidi,

) is export {
    my PDF::Content::Text::Box $tb .= new:
        :$text,
        :$font, :$font-size, :$kern, # <== note font information is rw
        #:$squish, # valign shouldn't be used with a text-box
        :$align, :$width, # :$height, # not directly constraining it
        :$indent,
        #:$verbatim,
    ;
    # the text box object has these rw attributes:
    #   constrain-height
    #   constrain-width
    #
    $tb
}

sub make-font-sample-doc(
    #   make-font-sample-doc $file,
    #         :%opts, :$debug;
    $file,    # the desired font file
    #===========================================
    # defaults are provided for the rest of the args
    :$fileHC is copy, # for the hex code
    :%opts,   # controls: media, font-size, embellishment
              # number of glyphs to show, etc.
    :$debug,
    ) is export {

    # create lines of glyph boxes out of a wrapped string of
    # chars

    say "DEBUG: in make-font-sample-page..." if $debug;

    my PDF::Lite $pdf .= new;
    # defaults
    # Letter or A4
    my $paper = "Letter";
    my Numeric $font-size = 18;
    my Numeric $font-size2 = 6;
    my Bool $embellish = False;

    my UInt    $ng-to-show = 0; # no limit on number of glyphs
    my UInt    $ns-to-show = 0; # no limit on number of sections
    my         @sn-to-show = []; # show only this section

    my $font = load-font :$file;
    my $fontHC;
    if $fileHC.defined {
        $fontHC = load-font :file($fileHC);
    }
    else {
        $fileHC = find-font :family<Helvetica>;
        $fontHC = load-font :file($fileHC);
    }

    my $ofil;

    if %opts and %opts.elems {
        # m=A4 - A4 media (default: Letter)
        # s=X  - font size (default: 18)
        # b=X  - add baseline and other data to the glyph box ($embellish)
        # ng=X - show max of X glyphs per section
        # ns=X - show first X sections
        # sn=X - show only section X
        # of=X - set $ofil to X
        for %opts.kv -> $k, $v {
            if $k eq "s"     { $font-size  = $v; }
            elsif $k eq "of" { $ofil       = $v; }
            elsif $k eq "ng" { $ng-to-show = $v.UInt; }
            elsif $k eq "ns" { $ns-to-show = $v.UInt; }
            elsif $k eq "sn" {
                my $w = $v.Str;
                say "DEBUG: \$w = '$w'" if 0;
                if $w ~~ /\h/ {
                    # split on ' '
                    @sn-to-show = $w.words;
                }
                elsif $w ~~ /','/ {
                    # split on ','
                    $w = $w.split(',');
                    @sn-to-show = $w.words;
                }
                else {
                    $w = $v.UInt;
                    @sn-to-show.push: $w;
                }
                if 0 {
                    say qq:to/HERE/;
                    DEBUG: \@sn-to-show:
                           {@sn-to-show.gist}
                    HERE
                    say "...and exit"; exit;
                }

            }
            elsif $k eq "b" {
                $embellish = True;
                # Results in showing the glyph's baseline, the glyph's origin,
                #   its horizontal-advance, and other data
            }
            elsif $k eq "m" {
                # A4 in mm: 210 x 297
                if $v ~~ /:i l/    { $paper = "Letter"; }
                elsif $v ~~ /:i 4/ { $paper = "A4";     }
                else { say "WARNING: Unknown media selection '$_'"; }
            }
        }
    }

    if $paper ~~ /:i letter / { $pdf.media-box = [0,0, 8.5*72, 11*72]; }
    else { $pdf.media-box = [0,0, cm2ps(21), cm2ps(29.7)]; }

    say "==== DEBUG: working font file; '{$file.IO.basename}'";
    my $fo = FaceFreeType.new: :$font-size, :$font;
    #my @ignored = $fo.get-ignored-list.list;
    my $ig = Ignore.new: :$file;
    if 1 or $debug {
        my @h;
        note "Contents of the Ignore instance:";
        my @i = $ig.ignored;
        for @i -> $dec {
            my $hex = dec2hex $dec.UInt;
            $hex = $hex.uc;
            @h.push: $hex;
        }
        @h = @h.unique;
        note "  $_" for @h.sort;
    }

    =begin comment
    if 0 {
        my $nchars = @ignored.elems;
        note "DEBUG: ignored glyphs for font '{$file.IO.basename}' (nchars: $nchars)";
        note "  '$_'" for @ignored;
        note "DEBUG: ignored glyphs for font '{$file.IO.basename}' (nchars: $nchars)";
    }
    =end comment

    if not $ofil.defined {
        $ofil = $fo.adobe-name ~ "-{$fo.extension}-sample.pdf";
    }
    else {
        # ensure name ends in ".pdf"
        unless $ofil ~~ /:i '.' pdf $/ {
            die "FATAL: output file name must end in '.pdf'";
        }
    }

    # need a font to show the hex codes in the glyph boxes
    # this is FreeSans (or equiv)
    my $foHC = FaceFreeType.new: :font-size($font-size2), :font($fontHC);

    # define margins, etc.
    my $lmarginw = 72; my $rmarginw = 72;
    my $tmarginh = 72; my $bmarginh = 72;
    my $pwidth   = $pdf.media-box[2];
    my $pheight  = $pdf.media-box[3];
    # content area
    my $cwidth   = $pwidth  - $lmarginw - $rmarginw;
    my $cheight  = $pheight - $tmarginh - $bmarginh;

    my ($ulx, $llx);
    $ulx = $llx = $lmarginw;
    # consider font heights for y coords for text
    my $uly = $pheight - $tmarginh - $fo.ascender;
    my $lly = $bmarginh + $fo.descender;
    say "DEBUG: \$ulx, \$uly = '$ulx', '$uly'" if $debug;

    # vertical space constants for starting a new section on a page
    #   or a single glyph row
    my $section-title-vspace = $font-size; # same as its font size .height
    # space for a section title plus two glyph rows
    my $widow-min-vspace  = $lly + 3*$section-title-vspace + 2*$glyph-box-height;
    my $orphan-min-vspace = $lly + $glyph-box-height;

    # Plan is to print all the Latin glyphs on as many pages as
    # necessary. Demark each set with its formal name.

    # create ALL the input data as Section objects FIRST
    #   THEN create the pages

    # max boxes on a line are limited by content width
    my $maxng = $cwidth div $glyph-box-width;
    say "Content width:   $cwidth" if $debug;
    say "Glyph box width: $glyph-box-width" if $debug;

    my $total-glyphs     = 0;
    my $total-glyph-rows = 0;
    my Section @sections;

    my Section $section;
    my $ns = 0; # number of sections (titles)
    SECTION: for %uni-titles.keys.sort -> $k {
        ++$ns;
        # decisions to be made
        if @sn-to-show.elems {
            # show ONLY selected sections
            my $show = 0;
            for @sn-to-show {
                $show = 1 if $_ == $ns;
            }
            my $nsn = @sn-to-show.elems;
            my $s = $nsn > 1 ?? 's' !! '';
            say "DEBUG: showing section $ns of $nsn section$s" if $debug;
            next SECTION unless $show;
        }
        elsif $ns-to-show {
            # show ONLY N sections
            last SECTION unless $ns <= $ns-to-show;
        }

        my $title = %uni-titles{$k}<title>;
        $section = Section.new: :$title, :number($ns);
        @sections.push: $section;

        my $ukey  = %uni-titles{$k}<key>;
        say "DEBUG: ukey = '$ukey'" if $debug;

        # this step converts all to individual HexStr objects and
        # reduces the set to ONLY the max number of glyphs to show
        my HexStr @gstrs = HexStrs2GlyphStrs %uni{$ukey}.words;
        # TODO: here is where we filter out zero-width and zero-height chars
        my @valid-gstrs;
        for @gstrs -> $hex {
            next if $ig.is-ignored: $hex.uc;
            # TODO how to handle properly???
            @valid-gstrs.push($hex.uc);
        }

        @gstrs = @valid-gstrs;
        if $ng-to-show and @gstrs.elems > $ng-to-show {
            @gstrs = @gstrs[0..^$ng-to-show];
        }

        my $nchars = @gstrs.elems;
        $total-glyphs += $nchars;
        say "DEBUG: \@s has $nchars single glyph strings" if $debug;

        # break @gstrs into $maxng length chunks
        my $glyph-row;
        while @gstrs.elems > $maxng {
            # get a chunk of length $maxng length per row
            $glyph-row = Glyph-Row.new: :$fo;
            for 0..^$maxng {
                $glyph-row.insert: @gstrs.shift;
                ++$total-glyph-rows;
            }
            # and finished with this row
            @sections.tail.insert: $glyph-row;
        }
        if @gstrs.elems {
            $glyph-row = Glyph-Row.new;
            $glyph-row.insert($_) for @gstrs;
            # and finished with this row
            @sections.tail.insert: $glyph-row;
        }

        if $debug {
            for @gstrs -> $hex {
                say "    seeing hex code range '$hex'";
            }
        }
    }

    say "Total number of glyphs: '$total-glyphs'" if $debug;
    say "Total number of glyphs per row: '$maxng'" if $debug;
    say "Total number of glyph rows: '$total-glyph-rows'" if $debug;

    #==== create the document ================
    my ($page, $g, @bbox);
    #==== TODO Make a cover with a TOC.
    if 0 {
    say "DEBUG: no TOC yet";
    my $dpage = $pdf.add-page;
    my $dg    = $dpage.gfx;
    # blank reverse
    my $dpage2 = $pdf.add-page;
    }

    #==== create the font glyph pages
    my $page-num = 0;
    my %page-nums;

    $page = $pdf.add-page; ++$page-num;
    say "NEW PAGE $page-num =============";
    $g = $page.gfx;

    # We have to start at the baseline of the content area
    #   and work down the page, breaking to a new page
    #   when we reach the bottom.
    # If the last line is a title, we stop and put it
    #   as the first item on a new page.
    # We also note the page number for each title
    #   entry for the TOC.

    my ($x, $y) = $ulx, $uly;
    my ($boxH);
    for @sections -> $section {
        my $text = $section.title;
        # check if enough room to get a couple of glyph rows following
        #if $y < ($lly + $fo.height + 2 * $glyph-box-height) {
        if $y < $widow-min-vspace  {
            $page = $pdf.add-page; ++$page-num;
            $x = $ulx;
            $y = $uly;
        }
        # write the section title
        $page.text: {
            .font = $fo.font, $fo.font-size;
            .text-position = $x, $y;
            @bbox = .print: $text, :align<left>;
        }
        $boxH = @bbox[3] - @bbox[1];
        $y -= $boxH;
        say "DEBUG: title: '$text'" if $debug;
        say "DEBUG: \$y = '$y'" if $debug;

        # now iterate over this section's glyph-rows
        ROW: for $section.glyph-rows -> $glyph-row {
            my @g = $glyph-row.glyphs;
            # check for enough vertical space for the row
            #if $y < ($lly + $glyph-box-height) { # <= orphan-min-vspace
            if $y < $orphan-min-vspace  {
                $page = $pdf.add-page; ++$page-num;
                say "NEW PAGE $page-num =============";
                $x = $ulx;
                $y = $uly;
            }
            # add a glyph box row
            for @g -> HexStr $hex {
                # convert to $hex number str
                #my $dec = $hs.ord;
                #my $hex = dec2hex $dec;
                # draw one box
                @bbox = make-glyph-box
                    $x, $y, # upper-left corner of the glyph box
                    :$fo,       # the loaded font being sampled
                    :$foHC,     # the loaded mono font used for the hex code
                    :$hex,      # char to be shown
                    :%opts, :$debug, :$page;
                # mv right for the next one
                $x += $glyph-box-width;
            }
            $boxH = @bbox[3] - @bbox[1];
            $x = $ulx;
            $y -= $boxH;
            if $y < $orphan-min-vspace  {
                $page = $pdf.add-page; ++$page-num;
                say "NEW PAGE $page-num =============";
                $x = $ulx;
                $y = $uly;
            }
        }
        $y -= 0.25 * 72;
        if $y < $widow-min-vspace  {
                $page = $pdf.add-page; ++$page-num;
                say "NEW PAGE $page-num =============";
                $x = $ulx;
                $y = $uly;
        }
    }

    $pdf.save-as: $ofil;
    compress $ofil, :quiet, :force, :dpi(300);
    say "See output file: '$ofil'";
}

sub make-glyph-box(
    $ulx, $uly,           # upper-left corner of the glyph box

    FaceFreeType :$fo!,   # the font being sampled
    FaceFreeType :$foHC!, # the mono font used for the hex code
    HexStr :$hex!,        # hex char to be shown
    :$page!,
    :%opts,

    # defaults
    :$line-width  = 0,
    :$line-width2 = 0,

    =begin comment
    # dimensions of a Unicode glyph box:
    #   width:  1.1 cm # width is good
    #   height: 1.4 cm
    :$glyph-box-width  = cm2ps(1.1), # width of the complete box
    :$glyph-box-height = cm2ps(1.4), # height of the complete box
    # dimensions of a Unicode glyph box:
    #   glyph baseline 0.5 cm from cell bottom
    #   hex code baseline 0.1 cm from cell bottom
    constant $glyph-box-baselineY  = cm2ps(0.5);
    constant $glyph-box-baselineY2 = cm2ps(0.1);
    =end comment

    :$hori-border-space = 4,
    :$vert-border-space = 4,
    :$debug,
    ) is export {

    # There are four bounding boxes we need:
    #   @glyph-box-bbox - the box containing everything to be shown on
    #                     the page for a single glyph and is defined
    #                     by global constants
    #   @font-bbox      - the box for the font collection
    #   @glyph-bbox     - the box for the glyph being shown
    #   @hex-bbox       - the box for the hex code being shown

    my $embellish = %opts<b>:exists ?? True !! False;

    # border coords ($ulx, $uly already defined);
    # which is the @glyph-box-bbox
    my ($llx, $lly, $lrx, $lry, $urx, $ury);
    $llx = $ulx;
    $lly = $uly - $glyph-box-height;
    $lrx = $llx + $glyph-box-width;
    $lry = $lly;
    $urx = $lrx;
    $ury = $uly;
    my @glyph-box-bbox = $llx, $lly, $urx, $ury;

    # Basically follow the format of the Unicode charts but with
    # possible addition of the decimal number.

    # The single glyph is a single char string from the $font object
    # and is centered horizonatally in a constant-width box which is
    # aS least the the size of the total font bbox

    # four-digit hex number at bottom in mono font (4 chars normally)
    my $s = $hex.uc; # ensure uppercase
    # fill with leading zeros...
    while $s.chars < 4 {
        $s = '0' ~ $s;
    }

    my Str $glyph = hex2string $hex;
    #my Str $glyph = (hex2dec($hex)).chr;

    # the gfx block
    my $g = $page.gfx;
    $g.Save;
    $g.SetStrokeGray: 0;

    #$g.transform: :translate[$ulx, $uly];

    #=== border first ================================
    # the border
    $g.SetLineWidth: 0.5;
    $g.MoveTo: $ulx, $uly; # top left
    $g.LineTo: $llx, $lly; # bottom left
    $g.LineTo: $lrx, $lry; # bottom right
    $g.LineTo: $urx, $ury; # top right
    $g.ClosePath;
    $g.Stroke;
    #=== border first ================================

    # render as $page.text
    my @glyph-bbox;
    my @hex-bbox;
    # dimensions of a Unicode glyph box:
    #   glyph baseline 0.5 cm from cell bottom
    #   hex code baseline 0.1 cm from cell bottom
    $page.text: {
        # the glyph as a text string
        .font = $fo.font, $fo.font-size;
        .text-position = $llx + 0.5 * $glyph-box-width, $lly + $glyph-box-baselineY;
        @glyph-bbox = .print: $glyph, :align<center>;

        # the hex code (already a string)
        .font = $foHC.font, $foHC.font-size;
        .text-position = $llx + 0.5 * $glyph-box-width, $lly + $glyph-box-baselineY2;
        @hex-bbox = .print: $s, :align<center>;
    }

    my $char-width = @glyph-bbox[2] - @glyph-bbox[0];
    if 0 and $debug and $char-width <= 0 {
        note qq:to/HERE/;
        WARNING: glyph hex code '$hex'
                 width = '$char-width'
                 need to handle earlier
        HERE
    }

    if $debug > 1 {
        say qq:to/HERE/;
        DEBUG:
            First \@glyph-bbox = '{@glyph-bbox.gist}'
            First \@hex-bbox   = '{@hex-bbox.gist}'
        HERE
    }

    # dimensions of a Unicode glyph box:
    #   glyph baseline 0.5 cm from cell bottom
    #   hex code baseline 0.1 cm from cell bottom
    # dimensions of a Unicode glyph box:
    #   hex code font height: 0.15 cm
    #   hex code stroke gray 0.5

    if not $embellish {
        say "DEBUG: Finish embellish";
    }
    my $V-len      = 3; # vertical tick
    my $bar-leftX  = 0; # set at origin
    my $bar-rightX = 0; # set at glyph advance-width
    my $bar-len    = 0; # glyph advance-width less origin

    # EMBELLISH
    # TODO: draw baseline the length of the font max-advance-width
    #       put a short vertical line at the origin and the advance
    #         width and the glyph width
    #       draw lines at the font height and previous baselines

    # stroke the baselines
    $g.SetLineWidth: 0;
    $g.MoveTo: $llx, $lly + $glyph-box-baselineY;
    $g.LineTo: $lrx, $lly + $glyph-box-baselineY;
    $g.Stroke;
    $g.MoveTo: $llx, $lly + $glyph-box-baselineY2;
    $g.LineTo: $lrx, $lly + $glyph-box-baselineY2;
    $g.Stroke;

    =begin comment
    # hack: scale it
    my @fbbox = font-bbox $font, :$font-size;
    my $font-width  = @fbbox[2] - @fbbox[0];
    my $font-height = @fbbox[3] - @fbbox[1];
    =end comment

    # stroke the previous baseline
    my $h  = $fo.height; # $font.height * $font-size;
    my $by = $lly + $glyph-box-baselineY + $h;

    if $debug > 1 {
        say qq:to/HERE/;
        DEBUG:
            Font height: '{$fo.height}' # it should be scaled
            Previous baseline height on the page: '$by'
        HERE
    }

    $g.MoveTo: $llx, $lly + $glyph-box-baselineY + $h;
    $g.LineTo: $lrx, $lly + $glyph-box-baselineY + $h;
    $g.Stroke;

    # stroke the fonts' max ascender
    $g.MoveTo: $llx, $lly + $glyph-box-baselineY + $fo.ascender;
    $g.LineTo: $lrx, $lly + $glyph-box-baselineY + $fo.ascender;
    $g.Stroke;

    # stroke the fonts' min descender
    $g.MoveTo: $llx, $lly + $glyph-box-baselineY + $fo.descender;
    $g.LineTo: $lrx, $lly + $glyph-box-baselineY + $fo.descender;
    $g.Stroke;

    $g.Restore;

    # return the glyph-box bbox
    $llx, $lly, $urx, $ury;
}

sub print-text-box(
    # text-box
    $x is copy, $y is copy,
    :$text!,
    :$page!,
    # defaults
    :$font-size = 12,
    :$fnt = "t", # key to %fonts, value is the loaded font
    # optional constraints
    :$width,
    :$height,
    ) is export {

    # TODO fill in
    # A text-box is resusable with new text only. All other
    # attributes are rw but font and font-size are fixed.

} # sub print-text-box

sub print-text-line(
    ) is export {

    # TODO fill in
    =begin comment
    $page.graphics: {
        my $gb = "GBUMC";
        my $tx = $cx;
        my $ty = $cy + ($height * 0.5) - $line1Y;
        .transform: :translate($tx, $ty); # where $x/$y is the desired reference point
        .FillColor = color White; #rgb(0, 0, 0); # color Black
        .font = %fonts<hb>, #.core-font('HelveticaBold'),
                 $line1size; # the size
        .print: $gb, :align<center>, :valign<center>;
    }
    =end comment

} # print-text-line

sub draw-box-clip(
    # starting position, default is
    # upper left corner
    $x, $y,
    :$width!,
    :$height!,
    :$page!,
    :$stroke-color = (color Black),
    :$fill-color   = (color White),
    :$linewidth = 0,
    :$fill is copy,
    :$stroke is copy,
    :$clip is copy,
    :$position = "ul", # ul, ll, ur, lr
    :$debug,
    --> List # @bbox
    ) is export {
    $fill   = 0 if not $fill.defined;
    $stroke = 0 if not $stroke.defined;
    $clip   = 0 if not $clip.defined;
    # what if none are defined?
    if $clip {
        # MUST NOT TRANSFORM OR
        # TRANSLATE
        ($fill, $stroke) = 0, 0;
    }
    else {
        # make stroke the default
        $stroke = 1 if not ($fill or $stroke);
    }

    my ($llx, $lly, $urx, $ury);
    my @bbox; # llx, lly, width, height

    my $g = $page.gfx;
    $g.Save if not $clip; # CRITICAL

    # NO translation
    if not $clip {
        $g.SetLineWidth: $linewidth;
        $g.StrokeColor = $stroke-color;
        $g.FillColor   = $fill-color;
    }

    # draw the path
    $g.MoveTo: $llx, $lly;
    $g.LineTo: $llx+$width, $lly;
    $g.LineTo: $llx+$width, $lly+$height;
    $g.LineTo: $llx       , $lly+$height;
    $g.ClosePath;

    if not $clip {
        if $fill and $stroke {
            $g.FillStroke;
        }
        elsif $fill {
            $g.Fill;
        }
        elsif $stroke {
            $g.Stroke;
        }
        else {
            die "FATAL: Unknown drawing status";
        }
        $g.Restore;
    }
    else {
        $g.Clip;
        $g.EndPath;
    }

    @bbox
} # sub draw-box-clip

sub rlineto(
    $x, $y,
    :$gfx!,
    :$debug,
    ) is export {
    # must have a current point
    my $g = $gfx;
    my $cp = $g.current-point;
    if not $cp.defined {
        say "WARNING: current point is not defined. Setting it to '0, 0'";
        $cp = [0, 0];
        $g.MoveTo: 0, 0;
    }
    my $xdelta = $x;
    my $ydelta = $y;
    $g.LineTo: $xdelta, $ydelta;
}

sub show-zero-chars($file, :$debug) is export {
    # for a font, determine zero-width and zero-height
    # glyps
    my $font = load-font :$file;
    my $fo = Font::Utils::FreeFaceType.new: :$font, :size(12);
    my @i;
    for $fo.ignored, $fo.vignored -> $dec {
        my $hex = dec2hex $dec;
        say "DEBUG: dec: '$dec' => '$hex'" if $debug;
    }
}

=begin comment
sub font-bbox(
    Font::Utils::FaceFreeType $fo,
    :$debug
    --> List
    ) is export {
    # Returns the scaled bounding box for the font collection
    =begin comment
    my $units-per-EM = $fo.face.units-per-EM;
    my $uheight = $fo.face.height:
    my $uwidth  = $fo.face.width;
    # return $unscaled * $font-size / $units-per-EM;
    my $width  = $uwidth  * $font-size / $units-per-EM;
    my $height = $uheight * $font-size / $units-per-EM;
    =end comment
    0, 0, $fo.width, $fo.height;
}
=end comment
