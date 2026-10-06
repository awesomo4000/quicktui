// QuickTUI adapter for pinned Sucrase 3.35.1 internals. Loader realm only.
import {transform, getVersion} from "sucrase/dist/esm/index.js";
import {parse} from "sucrase/dist/esm/parser/index.js";
import identifyShadowedGlobals from "sucrase/dist/esm/identifyShadowedGlobals.js";
import {IdentifierRole, isTopLevelDeclaration} from "sucrase/dist/esm/parser/tokenizer/index.js";
import {TokenType} from "sucrase/dist/esm/parser/tokenizer/types.js";

function identifier(code, token) {
  // The parser has already validated the identifier. Normalize escape spelling
  // so `pr\u006fcess` and `process` participate in the same scope analysis.
  return code.slice(token.start, token.end).replace(/\\u(?:\{([0-9a-fA-F]+)\}|([0-9a-fA-F]{4}))/g,
    (_, point, unit) => String.fromCodePoint(parseInt(point || unit, 16)));
}
function analyze(code, options, names) {
  const {tokens, scopes} = parse(code, !!options.jsx, !!options.typescript, false);
  const processor = {tokens, identifierNameForToken: token => identifier(code, token)};
  identifyShadowedGlobals(processor, scopes, names);
  // Sucrase's helper handles nested declarations; module-level bindings must
  // also shadow loader defines and the injected CommonJS require.
  const top = new Set(tokens.filter(t => !t.isType && isTopLevelDeclaration(t))
    .map(t => identifier(code, t)));
  const free = token => token && token.type === TokenType.name && !token.isType &&
    !token.shadowsGlobal && !top.has(identifier(code, token)) &&
    [IdentifierRole.Access, IdentifierRole.ObjectShorthand].includes(token.identifierRole);
  return {tokens, free};
}
function replacementExpression(value) {
  // Bare identifier/member replacements are already primary expressions.
  // Parenthesizing them can turn a following statement into a continued call:
  // a.b()\n x.y() must not become (b.c)()\n (y)().
  const first = value.charCodeAt(0);
  if ((first >= 65 && first <= 90) || (first >= 97 && first <= 122) || value[0] === '_' || value[0] === '$') {
    const tokens = parse(value, false, false, false).tokens.filter(t => t.type !== TokenType.eof);
    if (tokens.length % 2 === 1 && tokens.every((t, i) => t.type === (i % 2 ? TokenType.dot : TokenType.name))) return value;
  }
  return '(' + value + ')';
}
function rewriteDefines(code, options, definitions) {
  const entries = Object.entries(definitions).map(([key, value]) => ({parts: key.split('.'), value: replacementExpression(value)}));
  const {tokens, free} = analyze(code, options, new Set(entries.map(e => e.parts[0])));
  const edits = [];
  for (let i = 0; i < tokens.length; i++) {
    if (!free(tokens[i])) continue;
    for (const {parts, value} of entries) {
      if (identifier(code, tokens[i]) !== parts[0]) continue;
      let end = i;
      let matches = true;
      for (let j = 1; j < parts.length; j++) {
        if (tokens[end + 1]?.type !== TokenType.dot ||
            tokens[end + 2]?.type !== TokenType.name || identifier(code, tokens[end + 2]) !== parts[j]) {
          matches = false; break;
        }
        end += 2;
      }
      if (!matches) continue;
      const prefix = tokens[i].identifierRole === IdentifierRole.ObjectShorthand ? parts[0] + ':' : '';
      edits.push({start: tokens[i].start, end: tokens[i].end, value: prefix + value});
      // Remove only tokens, preserving comments and line breaks between them.
      for (let j = i + 1; j <= end; j++) edits.push({start: tokens[j].start, end: tokens[j].end, value: ''});
      i = end;
      break;
    }
  }
  let result = '', position = 0;
  for (const edit of edits) {
    result += code.slice(position, edit.start) + edit.value;
    position = edit.end;
  }
  return result + code.slice(position);
}
function inspectRequires(code, options = {}) {
  const {tokens, free} = analyze(code, options, new Set(['require']));
  const specifiers = [];
  let usesRequire = false;
  for (let i = 0; i < tokens.length; i++) {
    if (!free(tokens[i]) || identifier(code, tokens[i]) !== 'require') continue;
    usesRequire = true;
    if (tokens[i + 1]?.type !== TokenType.parenL || tokens[i + 2]?.type !== TokenType.string) continue;
    const next = tokens[i + 3]?.type === TokenType.comma ? i + 4 : i + 3;
    if (tokens[next]?.type !== TokenType.parenR) continue;
    const token = tokens[i + 2];
    // Only a parser-validated string token reaches eval, never an expression.
    // Use the JS engine to decode all JS string escapes and line continuations.
    specifiers.push((0, eval)('(' + code.slice(token.start, token.end) + ')'));
  }
  return {usesRequire, specifiers};
}
function commonJsNames(code, options = {}) {
  const names = new Set(['require', 'module', 'exports']);
  const {tokens, free} = analyze(code, options, names);
  return [...new Set(tokens.filter(t => free(t) && names.has(identifier(code, t))).map(t => identifier(code, t)))];
}
globalThis.__sucrase = {transform, version: getVersion(), rewriteDefines, inspectRequires, commonJsNames};
