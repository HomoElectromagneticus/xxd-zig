# xxd-zig

## à propos

This project attempts to clone the behavior of the `xxd` command-line utility in the [Zig programming language](https://ziglang.org). The goal of the project is for the author to learn something about the Zig language.

This project uses [the CLAP library v0.10.0](https://github.com/Hejsil/zig-clap/releases/tag/0.10.0) for command-line argument parsing.

The original `xxd` is packaged with `vim`: [https://github.com/vim/vim/tree/master/src/xxd](https://github.com/vim/vim/tree/master/src/xxd).

## TODO

 - allow reversing hex dumps back into "normal" files
 - see if we can't make the binary dump format faster by not using zig's print
   formating code and instead rolling our own
 - write more tests
 - add linebreaks to the "plain" dump as xxd does
 - look into using a different memory allocator
 - test for memory leaks
 - improve error handling for the command-line arguments
