# xxd-zig

## À propos

This project attempts to clone the behavior of the `xxd` command-line utility in the [Zig programming language](https://ziglang.org). The goal of the project is for the author to learn something about the Zig language.

This project uses [the CLAP library v0.10.0](https://github.com/Hejsil/zig-clap/releases/tag/0.10.0) for command-line argument parsing.

The original `xxd` is packaged with `vim`: [https://github.com/vim/vim/tree/master/src/xxd](https://github.com/vim/vim/tree/master/src/xxd).

## What differences does this program have from the original `xxd`?

- When using the "plain" postscript output, you may render the data in binary
- You may reverse "plain" postscript dumps of binary and hex data
- Speed: this program is between about 60 % and 2500 % faster than `xxd`, depending on the options used and file size
- Size: this program's binary is about two (3) times larger than `xxd`
- Improved error handling and messaging for reverse mode
- Reverse mode is more flexible: you don't need to exactly match the dump options in order to get a successful reversal
- You may use an odd-number of columns in the output, for whatever strange
  reason you may want to do that

## Remaining to-do items

 - write more tests
 - choose a better name - "xzd" or "zxd" ?

## Usage

```
Usage:
    xxd-zig <options> <filename>

    If --string is not set and a filename not given, the
    program will read from stdin. If more than one filename
    is passed in, only the first will be considered.

Options:
    -a                     Toggle autoskip: A '*' replaces null lines
    -b, --binary           Binary digit dump, default is hex
    -C                     Capitalise variable names in C include file style (-i)
    -c, --columns <INT>    Dump <INT> per line, default 16
    -d                     Show offset in decimal and not in hex
    -e                     Little-endian dump (default big-endian)
    -g <INT>               Group the output in <INT> bytes, default 2
    -h, --help             Display this help and exit
    -i                     Output in C include file style
    -l, --len <INT>        Stop writing after <INT> bytes
    -n <STR>               Set the variable name for C include file style (-i)
    -o, --offset <INT>     Add an offset to the displayed file position
    -p                     Plain dump, no formatting
    -r                     Reverse mode: convert dump into binary
    -s, --seek <INT>       Start at <INT> bytes absolute
        --string <STR>     Optional input string (ignores FILENAME and stdin)
    -u                     Use upper-case hex letters, default is lower
    -R                     Disable color output
    <FILENAME>             Path of file to convert to hex
```
