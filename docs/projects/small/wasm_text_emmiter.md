# WebAssembly Text Emitter

## Goal
Generate readable WebAssembly Text Format (`.wat`) from the compiler's existing AST or intermediate representation.

## Features
- Emit valid WebAssembly modules and functions.
- Support parameters, return values, and local variables.
- Generate numeric constants and arithmetic instructions.
- Support function exports.
- Report unsupported language constructs.
- Produce consistently formatted output.

## Implementation
1. Inspect the existing AST and code generator.
2. Implement a WAT emitter for basic functions and expressions.
3. Add variables, types, and exports.
4. Integrate the emitter into the compiler pipeline.
5. Validate generated WAT using an available WebAssembly tool.

## Success Criteria
The compiler can generate readable, valid `.wat` files for its supported language subset.