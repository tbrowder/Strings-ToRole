[![Actions Status](https://github.com/tbrowder/Strings-ToRole/actions/workflows/linux.yml/badge.svg)](https://github.com/tbrowder/Strings-ToRole/actions) [![Actions Status](https://github.com/tbrowder/Strings-ToRole/actions/workflows/macos.yml/badge.svg)](https://github.com/tbrowder/Strings-ToRole/actions) [![Actions Status](https://github.com/tbrowder/Strings-ToRole/actions/workflows/windows.yml/badge.svg)](https://github.com/tbrowder/Strings-ToRole/actions)

NAME
====

**Strings::ToRole** - Creates a file defining a named 'role' from a list of strings

SYNOPSIS
========

```raku
use Strings::ToRole;
my @s = [
    attr1 value1 # value1 is a string
    attr2 32     # Numeric
    attr3 False  # Bool
    attr3 "/path/file.pff" # IO::Path
];
my $role-name = "MyRole";
my $role-file = "myrole.txt";
strings2role @s, :$role-name, :$role-file;
```

DESCRIPTION
===========

**Strings::ToRole** produces a text file that can be used to define a Raku named `role` so a using Raku `class` can be instantiated with it.

NOTE: *The generated role file, when used by a class, gets compiled into usable class member BEFORE the class is constructed, so the role's attributes and methods can be used to complete the construction of the using class.*

The role file
-------------

The text file defining the role looks like this:

The class file
--------------

That file then can be used to provide data to define a Raku `class` by doing this:

    # insert code from file "myrole.txt" here...
    class MyClass does MyRole is export {
       # more code that uses the data in the role MyRole
       # ...
    }

The user is free to crreate a collection of useful role files to mix and match to define other useful classes.

AUTHOR
======

Tom Browder <tbrowder@acm.org>

COPYRIGHT AND LICENSE
=====================

© 2025 Tom Browder

This library is free software; you may redistribute it or modify it under the Artistic License 2.0.

