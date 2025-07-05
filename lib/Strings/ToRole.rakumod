unit module Strings::ToRole;

use Text::Utils :strip-comment;

class DLine { 
    has $.name  is rw is required;
    has $.value is rw is required;
    has $.type = "Str"; # defauld
}

sub parse-data-line(
    Str $line,
    --> List
    ) is export {
}

sub create-role(
    # lines with: attr-name attr-value attr-type
    $file where *.IO.r, 
    :$role-name!,
    :$role-file is copy,
    :$debug,
    --> List
    ) is export {
    unless $role-file.defined {
        my $s = $role-name.lc;
        $s ~~ s/'.' \S* $//;
        $role-name = "$s.txt";
    }

    my @dlines;

    for $file.IO.lines -> $line is copy {
        $line = strip-comment $line;
        next unless $line ~~ /\S/;
        my @w = parse-data-line $line;
        my $nw = @w.elems;
        unless 1 < $nw < 4 {
            die "FATAL: Expected 2 or 3 words but got $nw";
        }
        my $k = @w.shift;
        my $v = @w.shift;
        my $t;
        if @w.elems {
            $t = @w.shift;
        }
        my $dl = DLine.new: :name($k), :value($v);
        if $t {
            $dl.t = $t;
        }
        @dlines.push: $dl;
    }
}

