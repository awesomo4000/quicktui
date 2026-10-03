// CommonJS runtime for the source-module loader.
//
// Evaluated twice: once in the loader realm, where it executes vendored
// CommonJS packages only to discover their export names, and once in the
// application realm, where it executes them for real. The host object supplies
//   resolve(specifier, fromId) -> canonical module id
//   format(id) -> "cjs" | "esm"
//   compile(id) -> function (exports, require, module, __filename, __dirname)
//   importSync(source, name) -> namespace of an ES module graph evaluated now
// require() of an ES module returns its namespace when the graph has no
// top-level await, matching how the bundle's lazy initializers behaved.
// Plain JavaScript: this file is loaded before the TypeScript transform exists.
(function (global) {
  "use strict";
  function createCommonJs(host) {
    const cache = new Map();
    function load(id) {
      const cached = cache.get(id);
      if (cached) return cached.exports;
      const module = { id, exports: {}, loaded: false };
      cache.set(id, module);
      try {
        if (host.format(id) === "esm") {
          module.exports = host.importSync(`import * as ns from ${JSON.stringify(id)};\nexport { ns };\n`, `<require ${id}>`);
        } else {
          const body = host.compile(id);
          const directory = id.slice(0, id.lastIndexOf("/")) || "/";
          body.call(module.exports, module.exports, requireFrom(id), module, id, directory);
        }
      } catch (error) {
        cache.delete(id);
        throw error;
      }
      module.loaded = true;
      return module.exports;
    }
    function requireFrom(id) {
      return (specifier) => load(host.resolve(specifier, id));
    }
    return { load, requireFrom, cache };
  }
  Object.defineProperty(global, "__quicktuiCreateCommonJs", { value: createCommonJs, configurable: true });
})(globalThis);
