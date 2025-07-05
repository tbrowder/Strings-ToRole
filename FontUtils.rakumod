unit module FontFactory::Font::Utils; # <== to become a separate module repo

use QueryOS;
use YAMLish;

sub rescale(
    $font,
    :$debug,
    --> Numeric
    ) is export {
    # Given a font object with its size setting (.size) and a string of text you
    # want to be an actual height X, returns the calculated setting
    # size to achieve that top bearing.
}

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
}

sub to-string($cplist, :$debug --> Str) is export {
    # Given a list of hex codepoints, convert them to a string repr
    # the first item in the list may be a string label
    my @list;
    if $cplist ~~ Str {
        @list = $cplist.words;
    }
    else {
        @list = @($cplist);
    }
    if @list.head ~~ Str { @list.shift };
    my $s = "";
    for @list -> $cpair {
        say "char pair '$cpair'" if $debug;
        # convert from hex to decimal
        my $x = parse-base $cpair, 16;
        # get its char
        my $c = $x.chr;
        say "   its character: '$c'" if $debug;
        $s ~= $c
    }
    $s
}

sub hex2dec($hex, :$debug) is export {
    # converts an input hex sring to a decimal number
    my $dec = parse-base $hex, 16;
    $dec;
}

sub bin-cmp(
    $file1, 
    $file2, 
    # cmp options
    :$s = True,  # silent
    :$l = False, # list bytes differing and their values
    :$b = False, # list bytes differing
    :$n = 0,     # list first n bytes (default: 0 - list all)
    :$debug, 
    --> List
    ) is export {
    # Runs Gnu 'cmp' and compares the two inputs byte by byte
    # Returns a List whose first value is the error code
    #   and the rest are any data from :out and :err

    # build the command
    my $cmd = "cmp";
     
    if $l {
        $cmd ~= " -l";
    }
    elsif $b {
        $cmd ~= " -b";
    }
    else{
        $cmd ~= " -s";
    }

    # modifiers
    if $n {
        $cmd ~= " -n$n";
    }
    $cmd ~= " $file1 $file2";
    my $proc = run($cmd.words, :out, :err);
    my $err = $proc.exitcode; 

    my @lines  = $proc.out.slurp(:close).lines;
    my @lines2 = $proc.err.slurp(:close).lines;
    if 0 and $debug {
        if $err == 0 {
            say "DEBUG: no diffs found";
        }
        else {
            say "  DEBUG: byte differences:";
            for @lines {
                say "    $_";
            }
            for @lines2 {
                say "    $_";
            }
        }
    }
    $err, |@lines, |@lines2
}

=finish

# to be exported when the new repo is created
sub help is export {
    print qq:to/HERE/;
    Usage: {$*PROGRAM.basename} <mode>

    Modes:
      a - all
      p - print PDF of font samples
      d - download example programs
      L - download licenses
      s - show /resources contents
    HERE
    exit
}

sub with-args(@args) is export {
    for @args {
        when /:i a / {
            exec-d;
            exec-p;
            exec-L;
            exec-s;
        }
        when /:i d / {
            exec-d
        }
        when /:i p / {
            exec-p
        }
        when /:i L / {
            exec-L
        }
        when /:i s / {
            exec-s
        }
        default {
            say "ERROR: Unknown arg '$_'";
        }
    }
}

# local subs, non-exported
sub exec-d() {
    say "Downloading example programs...";
}
sub exec-p() {
    say "Downloading a PDF with font samples...";
}
sub exec-L() {
    say "Downloading font licenses...";
}
sub exec-s() {
    say "List of /resources:";
    my %h = get-resources-hash;
    my %m = get-meta-hash;
    my @arr = @(%m<resources>);
    for @arr.sort -> $k {
        say "  $k";
    }
}
