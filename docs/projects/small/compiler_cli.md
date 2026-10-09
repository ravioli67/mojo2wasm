# Compiler Command-Line Interface

## Goal
Create a consistent CLI for invoking and inspecting Mojo2Wasm.

## Features
- `build`: compile a source file.
- `tokens`: display lexer output.
- `ast`: display the parsed syntax tree.
- `emit-wat`: generate WebAssembly text.
- `--help`: display commands and usage.
- `--version`: display the compiler version.
- Support input/output paths and meaningful exit codes.

## Implementation
1. Inspect the current compiler entry point.
2. Add argument parsing.
3. Connect commands to existing compiler modules.
4. Handle file errors and compilation diagnostics.
5. Document command usage and examples.

## Success Criteria
Developers can compile and inspect source files through documented commands without modifying compiler code.