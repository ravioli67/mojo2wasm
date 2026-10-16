// A reference host for modules compiled by mojo_wasm.
//
// Programs that call print() import four functions from the "env" module and
// export their memory so the host can read string literals:
//
//   env.print_i64(Int)           env.print_f64(Float64)
//   env.print_bool(0 | 1)        env.print_str(pointer, length)
//
// print() puts a space between its arguments and a newline at the end; the
// compiled code does that itself by calling print_str with " " and "\n".
const fs = require("fs");

// Mojo prints 2.0 as "2.0" (JavaScript would print "2").
function formatFloat(x) {
  if (Number.isNaN(x)) return "nan";
  if (x === Infinity) return "inf";
  if (x === -Infinity) return "-inf";
  return Number.isInteger(x) && Math.abs(x) < 1e16 ? x.toFixed(1) : String(x);
}

// Loads a .wasm file. `write(text)` receives everything the program prints.
function loadWasm(file, write) {
  const bytes = fs.readFileSync(file);
  if (!WebAssembly.validate(bytes)) throw new Error(`${file} is not valid WebAssembly`);
  let memory = null;
  const decoder = new TextDecoder();
  const env = {
    print_i64: (v) => write(String(v)),
    print_f64: (v) => write(formatFloat(v)),
    print_bool: (v) => write(v ? "True" : "False"),
    print_str: (ptr, len) => write(decoder.decode(new Uint8Array(memory.buffer, ptr, len))),
  };
  const instance = new WebAssembly.Instance(new WebAssembly.Module(bytes), { env });
  memory = instance.exports.memory;
  return instance.exports;
}

module.exports = { loadWasm, formatFloat };
