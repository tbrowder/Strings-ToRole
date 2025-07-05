unit module Strings::ToRole;

#use MONKEY-SEE-NO-EVAL;
use MONKEY;

use Text::Utils :strip-comment;

#| Create a role from a list of "attribute-name value" strings.
#| Optionally provide a custom role name.
sub create-role-from-lines(
    @lines,
    Str :$role-name!,
) is export {
    my $role-code = "role $role-name \{\n";

    for @lines -> $line is copy {
        $line = strip-comment $line;
        next unless $line ~~ /\S/;
        my @w = $line.words;
        my $nw = @w.elems;
        unless $nw == 2 {
            die "FATAL: Only two words allowed, but string '$line' has $nw";
        }
        my $name  = @w.shift.Str;
        my $value = @w.shift.Str; # , $value) = $line.split(' ', 2);
        $role-code ~= "    has \$.{$name} = '\{$value}';\n";
    }

    $role-code ~= "}\n";

    try {
        EVAL $role-code;
        return ::($role-name);  # Return the role metaobject
    } // die "Failed to compile role: $!";
}
