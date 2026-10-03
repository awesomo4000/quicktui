// Source-module policy for QuickTUI: resolution, source patches, defines,
// and the TypeScript/JSX transform. A module-by-module port of the rules in
// scripts/bundle-app.ts, so source mode and the Bun bundle load the same graph.
//
// Runs in the loader realm next to vendor/sucrase/sucrase.js. The C host
// provides globalThis.__loaderHost and globalThis.__loaderConfig:
//   __loaderHost.read(path) -> string | undefined
//   __loaderHost.readBase64(path) -> string | undefined
//   __loaderHost.isFile(path) -> boolean
//   __loaderConfig = { root, entry, demoAssets }
// and calls the functions on globalThis.__loaderPolicy (see the end).
// Plain JavaScript: this file is loaded before the TypeScript transform exists.
(function (global) {
  "use strict";
  const host = global.__loaderHost;
  const config = global.__loaderConfig;
  const sucrase = global.__sucrase;

  // ---- POSIX paths -------------------------------------------------------
  function normalize(path) {
    const absolute = path.startsWith("/");
    const out = [];
    for (const part of path.split("/")) {
      if (part === "" || part === ".") continue;
      if (part === "..") { if (out.length && out[out.length - 1] !== "..") out.pop(); else if (!absolute) out.push(".."); continue; }
      out.push(part);
    }
    return (absolute ? "/" : "") + out.join("/");
  }
  const join = (...parts) => normalize(parts.join("/"));
  const dirname = (path) => path.slice(0, path.lastIndexOf("/")) || "/";
  const resolvePath = (from, spec) => spec.startsWith("/") ? normalize(spec) : join(from, spec);
  function extname(path) {
    const base = path.slice(path.lastIndexOf("/") + 1);
    const dot = base.lastIndexOf(".");
    return dot > 0 ? base.slice(dot) : "";
  }

  // ---- Layout (mirrors scripts/bundle-app.ts) ----------------------------
  const base = normalize(config.root);
  const native = join(base, "vendor/opentui/packages/core/src");
  const react = join(base, "vendor/opentui/packages/react/src");
  const platform = join(base, "js/platform");
  const vendorJs = join(base, "vendor/js");
  const entry = resolvePath(base, config.entry);
  const replacements = new Map([
    [join(native, "platform/ffi.ts"), join(platform, "ffi.ts")],
    [join(native, "platform/runtime.ts"), join(platform, "runtime.ts")],
    [join(react, "components/index.ts"), join(platform, "catalogue.ts")],
  ]);
  const aliases = new Map([
    ["quicktui", join(base, "js/app.ts")],
    ["quicktui/core", join(base, "js/core.ts")],
    ["quicktui/react", join(base, "js/app.ts")],
    ["quicktui/testing", join(base, "js/testing.ts")],
    ["quicktui/widgets", join(platform, "core.ts")],
    ["@opentui/core", join(platform, "core.ts")],
    ["events", join(vendorJs, "node_modules/events/events.js")],
    ["node:events", join(vendorJs, "node_modules/events/events.js")],
    ["buffer", join(vendorJs, "node_modules/buffer/index.js")],
    ["node:buffer", join(vendorJs, "node_modules/buffer/index.js")],
    ["node:util", "quicktui:util"],
    ["#opentui/runtime-assets", "quicktui:assets"],
  ]);
  const virtualSources = new Map([
    ["quicktui:assets", 'export const resolveNativeLibraryPath=()=>"quicktui:static";'],
    ["quicktui:fs-promises", 'export function open(){throw new Error("File image loading is unsupported; use NativeImage pixels")};export const stat=open;'],
    ["quicktui:util", 'export const inspect=Object.assign((value)=>String(value),{custom:Symbol.for("nodejs.util.inspect.custom")}); export default {inspect};'],
    ["quicktui:fs", 'export function existsSync(){throw new Error("Filesystem access is unsupported")}; export function writeFileSync(){throw new Error("Filesystem access is unsupported")};'],
  ]);

  // Bun's `define` equivalents, applied as text before the transform. The
  // lookbehind keeps `declare const __X__: T` intact for the TypeScript pass.
  let defineValues;
  function defines() {
    if (defineValues) return defineValues;
    const picture = config.demoAssets ? host.readBase64(join(base, "assets/dragon.jpg")) : "";
    const frames = [];
    if (config.demoAssets) for (let i = 0; i < 8; i++) frames.push(host.readBase64(join(base, `assets/dragon-frames/${i}.rgba`)));
    defineValues = [
      [/(?<!declare\s+(?:const|let|var)\s+)\b__SPRITE_FRAMES_BASE64__\b/g, JSON.stringify(frames)],
      [/(?<!declare\s+(?:const|let|var)\s+)\b__DEMO_PICTURE_BASE64__\b/g, JSON.stringify(picture)],
      [/\bprocess\.env\.NODE_ENV\b/g, '"production"'],
      [/\bprocess\.env\.DEV\b/g, '"false"'],
    ];
    return defineValues;
  }
  function applyDefines(text) {
    for (const [pattern, value] of defines()) if (pattern.test(text)) { pattern.lastIndex = 0; text = text.replace(pattern, () => value); }
    return text;
  }

  // Source patches, mirroring the onLoad hooks in scripts/bundle-app.ts.
  function patch(id, text) {
    if (/lib\/tree-sitter\/resolve-ft\.ts$/.test(id))
      return text.replace('import path from "node:path"', 'const path={posix:{basename:(s:string)=>s.split("/").filter(Boolean).pop()??""}};');
    if (/packages\/core\/src\/zig\.ts$/.test(id)) {
      text = text.replace(/let targetLibPath:[\s\S]*?(?=registerEnvVar\()/, 'const targetLibPath="quicktui:static"; const targetLibError=undefined;\n');
      const start = text.indexOf("const rawSymbols = dlopen(");
      const end = text.indexOf("if (env.OTUI_DEBUG_FFI", start);
      if (start < 0 || end < 0) throw new Error(`zig.ts patch anchors not found in ${id}`);
      return text.slice(0, start) + "const rawSymbols=dlopen(resolvedLibPath, {});\n\n  " + text.slice(end);
    }
    if (/packages\/core\/src\/lib\/index\.ts$/.test(id))
      return ["border", "RGBA", "styled-text", "extmarks"].map((name) => `export * from "./${name}.js";`).join("\n");
    if (/bun-ffi-structs\/dist\/index\.js$/.test(id)) {
      const start = text.indexOf("// src/structs_ffi.ts");
      if (start < 0) throw new Error(`bun-ffi-structs patch anchor not found in ${id}`);
      return `import {ptr,toArrayBuffer} from ${JSON.stringify(join(platform, "ffi.ts"))};\n` + text.slice(start);
    }
    return text;
  }

  // ---- Package resolution (Bun.resolveSync with the browser target) -------
  const extensions = [".ts", ".tsx", ".js", ".mjs", ".cjs", ".json"];
  const packageJsons = new Map();
  function readPackageJson(directory) {
    if (packageJsons.has(directory)) return packageJsons.get(directory);
    const text = host.read(join(directory, "package.json"));
    const value = text === undefined ? null : JSON.parse(text);
    packageJsons.set(directory, value);
    return value;
  }
  function probe(path) {
    if (host.isFile(path)) return path;
    for (const ext of extensions) if (host.isFile(path + ext)) return path + ext;
    const pkg = readPackageJson(path);
    if (pkg) {
      // Directory imports of packages (e.g. "../vendor/js/node_modules/marked")
      // follow `exports` first, as Bun does; marked's `browser` field is UMD.
      if (pkg.exports) { const target = resolveExports(pkg.exports, "."); if (target) { const found = probe(join(path, target)); if (found) return found; } }
      for (const field of ["module", "main"]) {
        if (typeof pkg[field] === "string") { const found = probe(join(path, pkg[field])); if (found) return found; }
      }
    }
    for (const ext of extensions) if (host.isFile(join(path, "index" + ext))) return join(path, "index" + ext);
    return null;
  }
  const conditions = new Set(["browser", "import", "module", "default"]);
  function exportTarget(target) {
    if (typeof target === "string") return target;
    if (Array.isArray(target)) { for (const item of target) { const found = exportTarget(item); if (found) return found; } return null; }
    if (target && typeof target === "object") {
      for (const key of Object.keys(target)) if (conditions.has(key)) { const found = exportTarget(target[key]); if (found) return found; }
    }
    return null;
  }
  function resolveExports(exportsField, subpath) {
    if (typeof exportsField === "string" || Array.isArray(exportsField) || !Object.keys(exportsField).some((k) => k.startsWith(".")))
      return subpath === "." ? exportTarget(exportsField) : null;
    if (subpath in exportsField) return exportTarget(exportsField[subpath]);
    for (const key of Object.keys(exportsField)) {
      const star = key.indexOf("*");
      if (star < 0) continue;
      const prefix = key.slice(0, star), suffix = key.slice(star + 1);
      if (subpath.startsWith(prefix) && subpath.endsWith(suffix) && subpath.length >= key.length - 1) {
        const target = exportTarget(exportsField[key]);
        if (target) return target.split("*").join(subpath.slice(prefix.length, subpath.length - suffix.length));
      }
    }
    return null;
  }
  function resolvePackage(spec, fromDirectory) {
    const parts = spec.split("/");
    const name = spec.startsWith("@") ? parts.slice(0, 2).join("/") : parts[0];
    const subpath = "." + spec.slice(name.length);
    for (let directory = fromDirectory; ; directory = dirname(directory)) {
      const packageDir = join(directory, "node_modules", name);
      const pkg = readPackageJson(packageDir);
      if (pkg) {
        if (pkg.exports) {
          const target = resolveExports(pkg.exports, subpath);
          if (target) { const found = probe(join(packageDir, target)); if (found) return found; }
        }
        const found = probe(join(packageDir, subpath));
        if (found) return found;
      }
      if (directory === "/") break;
    }
    throw new Error(`Cannot resolve package ${JSON.stringify(spec)} from ${fromDirectory}`);
  }

  // ---- Resolution (mirrors the onResolve hook) ----------------------------
  function resolve(spec, importer) {
    if (spec === "quicktui:entry" || virtualSources.has(spec)) return spec;
    if (aliases.has(spec)) return aliases.get(spec);
    if (spec === "react" || spec.startsWith("react/")) return resolvePackage(spec, vendorJs);
    if (spec === entry) return entry;
    if (["fs", "node:fs", "node:fs/promises"].includes(spec)) {
      if (!importer.startsWith(native + "/")) throw new Error(`Unsupported host import ${spec} from ${importer}`);
      return spec === "node:fs/promises" ? "quicktui:fs-promises" : "quicktui:fs";
    }
    if (spec.startsWith("node:") || spec.startsWith("bun:")) throw new Error(`Unsupported host import ${spec} from ${importer}`);
    if (!spec.startsWith(".") && !spec.startsWith("/")) return resolvePackage(spec, vendorJs);
    const directory = importer.startsWith("/") ? dirname(importer) : base;
    let resolved = resolvePath(directory, spec);
    if (resolved.endsWith(".js")) resolved = resolved.slice(0, -3) + ".ts";
    else if (!extname(resolved)) resolved += ".ts";
    if (resolved === join(native, "lib/tree-sitter/index.ts")) return join(platform, "plain-code.ts");
    if (replacements.has(resolved)) return replacements.get(resolved);
    if (host.isFile(resolved)) return resolved;
    const found = probe(resolvePath(directory, spec));
    if (!found) throw new Error(`Cannot resolve ${JSON.stringify(spec)} from ${importer}`);
    return found;
  }

  // ---- Source classification ----------------------------------------------
  const esmSyntax = /(?:^|[;\n])\s*(?:import\s*(?:[\w$]+\s*(?:,|from\b)|\{|\*|["'])|import\.meta\b|export\s*(?:default\b|const\b|let\b|var\b|function\b|class\b|async\b|\{|\*))/;
  function packageType(id) {
    for (let directory = dirname(id); ; directory = dirname(directory)) {
      const pkg = readPackageJson(directory);
      if (pkg) return pkg.type === "module" ? "module" : "commonjs";
      if (directory === "/" || directory === base) return "commonjs";
    }
  }
  // kind: ts | tsx | esm | cjs | text | json
  const sources = new Map();
  function source(id) {
    if (sources.has(id)) return sources.get(id);
    let result;
    if (id === "quicktui:entry") {
      // Same order as the bundle's entry: bootstrap first when hosted. Static
      // imports keep evaluation synchronous, like the bundle's IIFE.
      const imports = config.hosted ? [join(platform, "bootstrap.ts"), entry] : [entry];
      result = { kind: "esm", text: imports.map((path) => `import ${JSON.stringify(path)};`).join("\n") + "\n" };
    } else if (virtualSources.has(id)) {
      result = { kind: "ts", text: virtualSources.get(id) };
    } else {
      const raw = host.read(id);
      if (raw === undefined) throw new Error(`Cannot read module ${id}`);
      const ext = extname(id);
      const text = patch(id, raw);
      let kind;
      if (ext === ".ts" || ext === ".mts" || ext === ".cts") kind = "ts";
      else if (ext === ".tsx" || ext === ".jsx") kind = "tsx";
      else if (ext === ".md" || ext === ".txt") kind = "text";
      else if (ext === ".json") kind = "json";
      else if (ext === ".mjs") kind = "esm";
      else if (ext === ".cjs") kind = "cjs";
      else kind = packageType(id) === "module" || esmSyntax.test(text) ? "esm" : "cjs";
      result = { kind, text: kind === "text" || kind === "json" ? text : applyDefines(text) };
    }
    sources.set(id, result);
    return result;
  }
  function transformTypeScript(id, kind, text) {
    return fixEnumSelfNames(sucrase.transform(text, {
      transforms: kind === "tsx" ? ["typescript", "jsx"] : ["typescript"],
      jsxRuntime: "automatic", jsxImportSource: "react", production: true,
      disableESTransforms: true, filePath: id,
    }).code);
  }
  // Sucrase 3.35 lowers `enum Wrap { Wrap = 1 }` to
  //   (function (Wrap) { const Wrap = 1; Wrap[Wrap["Wrap"] = Wrap] = "Wrap"; })(Wrap || ...)
  // which redeclares the parameter. Rename the parameter in those IIFEs only.
  const enumBlock = /\(function \(([A-Za-z_$][\w$]*)\) \{([\s\S]*?)\}\)\(\1 \|\| \(\1 = \{\}\)\);/g;
  function fixEnumSelfNames(code) {
    return code.replace(enumBlock, (block, name, body) => {
      if (!new RegExp(`\\bconst ${name.replace(/\$/g, "\\$")} =`).test(body)) return block;
      const table = `${name}$enum`;
      const fixed = body.split(`${name}[${name}[`).join(`${table}[${table}[`).split(`; ${name}["`).join(`; ${table}["`);
      return `(function (${table}) {${fixed}})(${name} || (${name} = {}));`;
    });
  }

  // ---- CommonJS export discovery --------------------------------------------
  // Executes the CommonJS graph in this realm only to learn export names; the
  // application realm executes it again for real, in import order.
  const discovery = global.__quicktuiCreateCommonJs({
    resolve,
    format,
    compile: (id) => (0, eval)(commonJsBody(id)),
    importSync() { throw new Error("ES modules are not evaluated during export discovery"); },
  });
  const exportNames = new Map();
  const identifier = /^[A-Za-z_$][\w$]*$/;
  function namesOf(id) {
    if (exportNames.has(id)) return exportNames.get(id);
    let names = [];
    try {
      const value = discovery.load(id);
      if ((typeof value === "object" && value !== null) || typeof value === "function")
        names = Object.getOwnPropertyNames(value).filter((name) => name !== "default" && name !== "__esModule"
          && !(typeof value === "function" && ["length", "name", "prototype", "caller", "arguments"].includes(name)));
    } catch (error) {
      // Fall back to a lexical scan when discovery cannot run in this realm.
      const text = source(id).text;
      const found = new Set();
      for (const match of text.matchAll(/(?:^|[^.\w$])(?:module\.)?exports\.([A-Za-z_$][\w$]*)\s*=(?!=)/g)) found.add(match[1]);
      for (const match of text.matchAll(/Object\.defineProperty\(\s*(?:module\.)?exports\s*,\s*["']([^"']+)["']/g)) found.add(match[1]);
      found.delete("default"); found.delete("__esModule");
      names = [...found];
    }
    exportNames.set(id, names);
    return names;
  }
  function commonJsBody(id) {
    const { kind, text } = source(id);
    if (kind === "json") return `(function (exports, require, module) {module.exports = ${text}\n})`;
    if (kind === "text") return `(function (exports, require, module) {module.exports = ${JSON.stringify(text)}\n})`;
    if (kind !== "cjs") throw new Error(`require() of ES module ${id} is not supported; use import`);
    // Keep the body on the first line so error positions match the file.
    return `(function (exports, require, module, __filename, __dirname) {${text}\n})`;
  }
  function facade(id) {
    const names = namesOf(id);
    const lines = [
      `const __m = globalThis.__quicktuiRequire(${JSON.stringify(id)});`,
      `export default (__m && __m.__esModule && "default" in __m) ? __m.default : __m;`,
    ];
    const bindings = names.map((name, index) => {
      lines.push(`const __e${index} = __m[${JSON.stringify(name)}];`);
      return identifier.test(name) && name !== "default" ? `__e${index} as ${name}` : `__e${index} as ${JSON.stringify(name)}`;
    });
    if (bindings.length) lines.push(`export { ${bindings.join(", ")} };`);
    return lines.join("\n") + "\n";
  }

  // ---- Host interface ---------------------------------------------------------
  // mode "module": ES module source for the QuickJS module loader.
  // mode "cjs": a function expression for the CommonJS runtime.
  // key() returns cache key material, or null when the output must not be cached.
  function format(id) {
    const { kind } = source(id);
    return kind === "cjs" || kind === "json" || kind === "text" ? "cjs" : "esm";
  }
  // ES modules that call require() (e.g. js/examples.ts) get a module-scoped
  // require on their first line, so line numbers are unchanged.
  const callsRequire = /\brequire\s*\(/;
  const declaresRequire = /\b(?:const|let|var|function|class)\s+require\b|\bimport\s+require\b/;
  function withRequire(id, code) {
    if (!callsRequire.test(code) || declaresRequire.test(code)) return code;
    return `const require = globalThis.__quicktuiRequireFrom(${JSON.stringify(id)}); ` + code;
  }
  // Literal require("...") calls in built code. Dynamic requires are invisible
  // here; images reject them at run time with "not in image".
  const requireCall = /(?:^|[^.\w$])require\s*\(\s*(["'])((?:\\.|(?!\1)[^\\\n])*)\1\s*\)/g;
  function requireSpecifiers(code) {
    const specs = [];
    for (const match of code.matchAll(requireCall)) specs.push(match[2]); // escapes in paths are not decoded
    return specs;
  }
  // Branches a build never takes (React's development builds) are left out of
  // facade keys and images. Override with __loaderConfig.exclude (a RegExp source).
  const excluded = new RegExp(config.exclude || "\\.development\\.js$");
  // The static CommonJS closure discovery would execute: ids in load order.
  function commonJsClosure(id, seen = new Set()) {
    if (seen.has(id)) return [...seen];
    seen.add(id);
    if (source(id).kind !== "cjs") return [...seen];
    for (const spec of requireSpecifiers(source(id).text)) {
      let target;
      try { target = resolve(spec, id); } catch { continue; }
      if (!excluded.test(target)) commonJsClosure(target, seen);
    }
    return [...seen];
  }
  function key(id, mode) {
    const { kind, text } = source(id);
    if (mode === "module" && kind === "cjs") {
      // A facade depends on every source its discovery run can execute.
      return "facade\0" + commonJsClosure(id).map((dep) => `${dep}\0${source(dep).kind}\0${source(dep).text}`).join("\0\0");
    }
    return `${kind}\0${text}`;
  }
  // [specifier, resolved id or null, "cjs" | "esm" | error message] for every
  // literal require in the built module; used to close module images over
  // require() targets that static imports do not reach.
  function requires(id, mode) {
    if (mode === "module" && source(id).kind === "cjs") return JSON.stringify([[id, id, "cjs"]]);
    const out = [];
    for (const spec of requireSpecifiers(build(id, mode))) {
      try {
        const target = resolve(spec, id);
        if (!excluded.test(target)) out.push([spec, target, format(target)]);
      } catch (error) {
        out.push([spec, null, String(error && error.message || error)]);
      }
    }
    return JSON.stringify(out);
  }
  const built = new Map();
  function build(id, mode) {
    const memo = `${mode}\0${id}`;
    if (built.has(memo)) return built.get(memo);
    const code = buildUncached(id, mode);
    built.set(memo, code);
    return code;
  }
  function buildUncached(id, mode) {
    const { kind, text } = source(id);
    if (mode === "cjs") return commonJsBody(id);
    if (kind === "ts" || kind === "tsx") return withRequire(id, transformTypeScript(id, kind, text));
    if (kind === "esm") return withRequire(id, text);
    if (kind === "cjs") return facade(id);
    if (kind === "text") return `export default ${JSON.stringify(text)};\n`;
    if (kind === "json") return `export default ${JSON.stringify(JSON.parse(text))};\n`;
    throw new Error(`Unknown module kind ${kind} for ${id}`);
  }
  Object.defineProperty(global, "__loaderPolicy", { value: Object.freeze({ resolve, format, key, build, requires, entry: "quicktui:entry" }) });
})(globalThis);
