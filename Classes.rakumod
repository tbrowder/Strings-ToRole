unit module PDF::GraphPaper::Classes;

use Text::Utils :strip-comment;
use PDF::GraphPaper::Subs;
use PDF::GraphPaper::Vars;

role DefaultAttributes {
    # 18 attributes with default values, in desired order
    has $.units is rw       = "in";       # default
    has $.media is rw       = "letter";   # default
    has $.orientation is rw = "portrait"; # default
    #=========================
    #== defaults for Letter paper
    has $.margins is rw       = 0.5 * 72;
    # allow for custom margins for each edge
    has $.margin-t is rw = -1; # -1 indicates not set
    has $.margin-b is rw = -1; # -1 indicates not set
    has $.margin-l is rw = -1; # -1 indicates not set
    has $.margin-r is rw = -1; # -1 indicates not set

    has $.cell-size-x is rw =  0.1 * 72; # desired minimum cell
                                     #   size (inches)
    has $.cell-size-y is rw =  0.1 * 72; # desired minimum cell
                                     #   size (inches)
    has $.page-width  is rw =  8.5 * 72;
    has $.page-height is rw = 11.0 * 72;

    has $.major-grids is rw = True;
    has $.minor-grids is rw = True;  # forced False if cells-per-grid
                                     #   is odd
    has $.cells-per-grid is rw = 10; # heavier line every X cells

    # standard linewidths in PS points
    # mid-grid line only for even number of cells-per-grid
    has $.cell-linewidth     is rw = 0;    # very fine line
    has $.mid-grid-linewidth is rw = 0.75; # heavier line width
                                           #  (for even cpg)
    has $.grid-linewidth is rw     = 1.40; # heavier line width

    # 6 more attrs
    has $.scale-t is rw = 0;
    has $.scale-b is rw = 0;
    has $.scale-l is rw = 0;
    has $.scale-r is rw = 0;
    has $.grid-origin-x is rw = 0;
    has $.grid-origin-y is rw = 0;

    method update-from-file(IO::Path $ifil) {
        for $ifil.IO.lines -> $line is copy {
            $line = strip-comment $line;
            next unless $line ~~ /\S/;
            my @w = $line.words;
            my $nw = @w.elems;
            unless $nw == 2 { 
                die "FATAL: Expected 2 words but got $nw";
            }
            my $k = @w.shift;
            my $v = @w.shift;
            with $k {
                # when x { $!x = $v }
                when "units" { 
                    $!units = $v } #               in
                #=begin comment
                when "media" { 
                    $!media = $v } #               letter
                when "orientation" {
                    $!orientation = $v } #    portrait
                when "margins" {
                    $!margins  = $v.Numeric } #   36
                when "margin-t" {
                    $!margin-t       = $v.Numeric } #   -1
                when "margin-b" {
                    $!margin-b       = $v.Numeric } #   -1
                when "margin-l" {
                    $!margin-l       = $v.Numeric } #   -1
                when "margin-r" {
                    $!margin-r       = $v.Numeric } #   -1
                when "cell-size-x" {
                    $!cell-size-x       = $v.Numeric } #   7.2
                when "cell-size-y" {
                    $!cell-size-y       = $v.Numeric } #   7.2
                when "page-width" {
                    $!page-width       = $v.Numeric } #   612
                when "page-height" {
                    $!page-height       = $v.Numeric } #   792
                when "major-grids" {
                    $!major-grids  =  $v.Bool} #  True
                when "minor-grids" {
                    $!minor-grids       =  $v.Bool } # True
                when "cells-per-grid" {
                    $!cells-per-grid       = $v.Numeric } #10
                when "cell-linewidth" {
                    $!cell-linewidth       = $v.Numeric } #0
                when "mid-grid-linewidth" {
                    $!mid-grid-linewidth   = $v.Numeric } #0.75
                when "grid-linewidth" {
                    $!grid-linewidth   = $v.Numeric } #1.4
                when "scale-t" { 
                    $!scale-t  = $v.Numeric } #0
                when "scale-b" { 
                    $!scale-b  = $v.Numeric } #0
                when "scale-l" { 
                    $!scale-l  = $v.Numeric } #0
                when "scale-r" {
                    $!scale-r   = $v.Numeric } #0
                when "grid-origin-x" {
                    $!grid-origin-x   = $v.Numeric } #0
                when "grid-origin-y" {
                    $!grid-origin-y   = $v.Numeric } #0
                #=end comment
                
                default { warn "WARNING: Unknown attribute '$_'" }
            }
        }
    }
}

class GPaper does DefaultAttributes is export {

    # an array of attribute names and current values as word pairs
    has @.attrs;
    has %.attr;

    submethod TWEAK {
        # attribute names in desired order
        # use @valid-keys from Vars;
        # an array of attr names and current values as word pairs

        # fill the attrs array with its attr names and current values
        # fill the attr hash by name and value for easy lookup

        # current attribute values from the role:
        my @role-attrs = self.^attributes;
        for @role-attrs -> $a {
            my $val = $a.get_value: self;
            my $data = "$a $val";
            if 0 {
                note "DEBUG: curr attr: $a";
                note "         attr val: $val";
            }
            # fill @.attrs
            @!attrs.push: $data;
            # fill %.attr
            %!attr{$a} = $val;
        }

        if $pdf-cnf.IO.r {
            # use the caller's attr values to update the class
            # instance
            my @data = read-specs-file $pdf-cnf;
            self.update-from-file: $pdf-cnf;
        }

    } # end of submethod TWEAK

    =begin comment
    method is-valid-key($key --> Bool) {
        if %valid-keys{$key}:exists {
            return True;
        }
        False
    }
    =end comment

    method show-spec {
        # attributes in desired order
        # we can use the @!attrs to get the data
        my $alen = 0;
        my @oattrs; # correct data, but $! stripped
        for self.attrs -> $s {
            my $a = $s.words.head;
            next if $a ~~ /^ '@!'/;
            next if $a ~~ /^ '%!'/;

            $a ~~ s/^'$!'//;
            my $len = $a.chars;
            $alen = $len if $len > $alen;
            my $v = $s.words.tail;
            my $data = "$a $v";
            @oattrs.push: $data;
        }

        my $ns = @oattrs.elems;
        say "\# Current list of $ns attributes and values:";
        for @oattrs -> $s {
            my $a = $s.words.head;
            my $v = $s.words.tail;
            # the desired, left justified key:
            say sprintf '%-*s  %s', $alen, $a, $v;
        }
    }

    method use-user-cnf() {
        return unless $pdf-cnf.IO.r;
        for $pdf-cnf.IO.lines -> $line is copy {
            $line = strip-comment $line;
            next unless $line ~~ /\S/;
            my @w = $line.words;
            my $nw = @w.elems;
            die "FATAL: Expected two words but got $nw";
            my $attr  = @w.shift;
            my $value = @w.shift;
            # how to update it? see docs...
            # my $attr = GPaper.^attributes(:X);
        }
        =begin comment
        # from doc search for "set_value"
        # method set_value(Mu $obj, Mu \new_val)
        #   Binds the value 'new_val' to this attribute of 
        #     object $obj.
        class A {
            has $!a = 5;
            method speak() { say $!a; }
        }
        # in line below, [0] is the first attr in the class 
        #   definition
        my $attr = A.^attributes(:local)[0]; 
        my $a = A.new;
        $a.speak; # OUTPUT: «5␤»
        $attr.set_value($a, 42);
        $a.speak; # OUTPUT: «42␤»
        =end comment

    } # end of method 'use-user-cnf'

} # end of exported class GPaper

class Scale is export {
    has $.llx      is rw = 0;
    has $.lly      is rw = 0;
    has $.length   is rw = 0;
    has $.angle    is rw where * ~~ /^ 0|90 $/;
    has $.location is rw where * ~~ /^ :i t|b|l|r/;

    submethod TWEAK {
    }
}
