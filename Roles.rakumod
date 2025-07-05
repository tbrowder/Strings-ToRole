unit module FontFactory::Roles;

class FontData is export {
    has UInt     $.number   is required; # field 1
    has Str      $.fullname is required; # field 2
    has Str      $.code;                 # field 3
    has Str      $.code2;                # field 4
    has Str      $.alias;                # field 5
    has IO::Path $.path     is required; # field 6
    
    submethod TWEAK {
        # fonts with $!number < 16 MUST have all 6 attributes defined
        if $!number < 16 {
            my @errs;
            my $err = 0;
            unless $!code.defined  { @errs.push: "undefined .code";  }
            unless $!code2.defined { @errs.push: "undefined .code2"; }
            unless $!alias.defined { @errs.push: "undefined .code2"; }
            my $ne = @errs.elems;
            if @errs {
                my $s = $ne > 1 ?? 's' !! '';
                note "FATAL: Font number $!number has $ne error$s:"; 
                note " $_" for @errs;
                die  "Early ending after fatal error$s.";
            }
        }
    }
}

