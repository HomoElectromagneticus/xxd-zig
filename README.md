# xxd-zig

## À propos

This project attempts to clone the behavior of the `xxd` command-line utility in the [Zig programming language](https://ziglang.org). The goal of the project is for the author to learn something about the Zig language.

This project uses [the CLAP library v0.10.0](https://github.com/Hejsil/zig-clap/releases/tag/0.10.0) for command-line argument parsing.

The original `xxd` is packaged with `vim`: [https://github.com/vim/vim/tree/master/src/xxd](https://github.com/vim/vim/tree/master/src/xxd).

## What advantages does this code have over the original `xxd`?

- When using the "plain" postscript output, you can render the data in binary
- You may use an odd-number of columns in the output, for whatever strange
  reason you may want to do that
- Speed: this program is between 10 % and 280 % faster than `xxd`, depending on
  the chosen output mode

## Remaining to-do items

 - allow reversing hex dumps back into "normal" files
 - see if we can't make the binary dump format faster by not using zig's print
   formating code and instead rolling our own
 - write more tests
 - look into using a different memory allocator for better performance
 - test for memory leaks
 - improve error handling for the command-line arguments
 - choose a better name - "xzd" ?
