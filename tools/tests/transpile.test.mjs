// Regression tests for the dashboard's Lua->Python transpiler.
//
// The transpiler lives inside zxtouch/zxtouch/http/index.html (the shipped
// dashboard), not in a module, so this harness extracts `function
// transpileLua(src) { ... }` by brace matching and evaluates it. Every case
// that must also RUN on device additionally asserts the emitted text is
// syntactically valid Python — that check is done here in JS by a
// conservative paren/quote balance plus the golden string itself; the real
// Python-side execution contract (zxRange/zxUnpackMatch/zxConcat/LuaDict)
// is covered by tools/tests/test_prelude.py.
//
// Run:  node --test tools/tests/transpile.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const HTML = path.join(here, '..', '..', 'zxtouch', 'zxtouch', 'http', 'index.html');
const STAGED = path.join(here, '..', '..', 'layout', 'Applications', 'zxtouch.app', 'index.html');

/** Extract the transpiler body. The shipped code defines `transpileLuaEx()`
 *  (returns `{ code, lineMap }`) plus a thin `transpileLua()` wrapper, so the
 *  body is sliced from `function transpileLuaEx(` to the wrapper's
 *  `function transpileLua(` — a brace/string scanner would not be robust here:
 *  the function contains regex literals whose quote characters defeat naive
 *  string-skipping. */
function extractTranspiler(source) {
  const at = source.indexOf('function transpileLuaEx(');
  assert.notEqual(at, -1, 'function transpileLuaEx() not found in dashboard HTML');
  const next = source.indexOf('function transpileLua(', at);
  assert.notEqual(next, -1, 'anchor function transpileLua() not found after transpileLuaEx()');
  const body = source.slice(at, next).trimEnd();
  assert.ok(body.endsWith('}'), 'extracted transpileLuaEx does not end with "}"');
  return body;
}

const src = readFileSync(HTML, 'utf8');
const transpileLuaEx = eval(`(${extractTranspiler(src)})`);

// ---------------------------------------------------------------- helpers

function py(src) { return transpileLuaEx(src).code; }

/** Rough syntax guard for the emitted code: balanced parens, no Lua
 *  leftovers (`end`, `local`, `~=`, `..` outside strings), no leaked
 *  \u0001 placeholders. */
function assertLooksLikePython(out) {
  assert.ok(!/\u0001/.test(out), `placeholder leaked: ${JSON.stringify(out)}`);
  assert.ok(!/\bend\b/.test(out), `Lua "end" leaked: ${JSON.stringify(out)}`);
  assert.ok(!/\blocal\b/.test(out), `Lua "local" leaked: ${JSON.stringify(out)}`);
  assert.ok(!out.includes('~='), `Lua "~=" leaked: ${JSON.stringify(out)}`);
  // `..` may only survive inside the vararg idiom `...`
  const noStrings = out.replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/g, '""');
  assert.ok(!/(?<!\.)\.\.(?!\.)/.test(noStrings), `Lua concat leaked: ${JSON.stringify(out)}`);
  const balance = (o, c) => (out.split(o).length - out.split(c).length);
  for (const [o, c] of [['(', ')'], ['[', ']'], ['{', '}']]) {
    assert.equal((out.match(new RegExp('\\' + o, 'g')) || []).length,
      (out.match(new RegExp('\\' + c, 'g')) || []).length,
      `unbalanced ${o}${c}: ${JSON.stringify(out)} (diff=${balance(o, c)})`);
  }
}

// ---------------------------------------------------------------- A1: for loops

test('numeric for with negative step iterates like Lua', () => {
  const out = py('for i = 10, 1, -1 do\n  log(i)\nend');
  // Must stop at 1 inclusive: with a -1 step, stop-1 does it.
  assert.match(out, /range\(10, \(1\)-1, -1\)/);
  assertLooksLikePython(out);
});

test('numeric for with positive literal step keeps exclusive-correct +1', () => {
  const out = py('for i = 1, 10, 2 do\n  log(i)\nend');
  assert.match(out, /range\(1, \(10\)\+1, 2\)/);
  const values = eval('[...Array(11).keys()].slice(1).filter(x => (x-1)%2===0)');
  assert.deepEqual(values, [1, 3, 5, 7, 9]);
});

test('numeric for without step includes the stop', () => {
  const out = py('for i = 1, 3 do\n  log(i)\nend');
  assert.match(out, /range\(1, \(3\)\+1\)/);
});

test('numeric for with a variable step delegates to zxRange', () => {
  const out = py('for i = 10, 1, s do\n  log(i)\nend');
  assert.match(out, /zxRange\(10, 1, s\)/);
  assertLooksLikePython(out);
});

test('one-line for uses the same header logic', () => {
  const out = py('for i = 10, 1, -1 do log(i) end');
  assert.match(out, /for i in range\(10, \(1\)-1, -1\):/);
  assert.ok(out.includes('log(i)'));
});

// ---------------------------------------------------------------- A2: multi-return

test('tapImage assignment unpacks via zxUnpackMatch (docs example)', () => {
  const out = py('local ok, x, y = tapImage("btn.png")\nif ok then log("Tapped at " .. x .. "," .. y) end');
  assert.match(out, /ok, x, y = zxUnpackMatch\(tapImage\("btn\.png"\)\)/);
  assertLooksLikePython(out);
});

test('swipeUntilImage assignment unpacks via zxUnpackMatch (docs example)', () => {
  const out = py('local ok, x, y = swipeUntilImage("target.png", "up", 15)\nif ok then tap(x, y) end');
  assert.match(out, /ok, x, y = zxUnpackMatch\(swipeUntilImage\("target\.png", "up", 15\)\)/);
  assertLooksLikePython(out);
});

test('findImage two-target assignment takes the coordinates', () => {
  const out = py('local x, y = findImage("a.png")\ntap(x, y)');
  assert.match(out, /_zx\d+ = zxUnpackMatch\(findImage\("a\.png"\)\)/);
  assert.match(out, /x, y = _zx\d+\[1], _zx\d+\[2]/);
  assertLooksLikePython(out);
});

test('multi-line unpack closes the wrapper and emits the tail', () => {
  // Continuation lines are trimmed by the buffer, like every other statement.
  const out = py('local ok, x, y = tapImage("a.png",\n  5)');
  assert.match(out, /^ok, x, y = zxUnpackMatch\(tapImage\("a\.png",\n5\)\)$/m);
  assertLooksLikePython(out);
  const two = py('local x, y = findImage("a.png",\n  0.9)');
  assert.match(two, /_zx\d+ = zxUnpackMatch\(findImage\("a\.png",\n0\.9\)\); x, y = _zx\d+\[1], _zx\d+\[2]/);
  assertLooksLikePython(two);
});

test('untouched calls stay plain statements', () => {
  const out = py('tapImage("a.png")\nsleep(1)');
  assert.equal(out, 'tapImage("a.png")\nsleep(1)');
});

// ---------------------------------------------------------------- JSON / Lua tables

test('jsonDecode result keeps Lua field access (user-reported shape)', () => {
  const out = py('local config = jsonDecode(raw)\n' +
                 'log("Loops: " .. config.loops)\n' +
                 'log("Delay: " .. config.delay .. "s")');
  assert.match(out, /^config = jsonDecode\(raw\)$/m);
  // Numbers may ride in a concat: the chain must go through zxConcat, not `+`.
  assert.match(out, /log\(zxConcat\("Loops: ", config\.loops\)\)/);
  assert.match(out, /log\(zxConcat\("Delay: ", config\.delay, "s"\)\)/);
  assertLooksLikePython(out);
});

test('positional Lua table becomes a Python list, not a set', () => {
  const out = py('local s = jsonEncode({1, 2, 3})');
  assert.match(out, /s = jsonEncode\(\[1, 2, 3]\)/);
  const out2 = py('local r = findColors({{0xFF0000, 0, 0}, {0x00FF00, 10, 0}}, 1)');
  assert.match(out2, /\[\[0xFF0000, 0, 0], \[0x00FF00, 10, 0]]/);
  assertLooksLikePython(out2);
});

test('keyed Lua table still becomes a Python dict', () => {
  const out = py('local t = jsonEncode({a = 1, b = "x"})');
  assert.match(out, /t = jsonEncode\(\{"a": 1, "b": "x"\}\)/);
});

test('empty table stays an empty dict for t[k] = v building', () => {
  const out = py('local t = {}\nt["k"] = 1');
  assert.match(out, /^t = \{\}$/m);
  assert.match(out, /^t\["k"\] = 1$/m);
});

test('mixed nested tables converge in one pass', () => {
  const out = py('httpPost("https://x", jsonEncode({a = {b = 1}, c = {2, 3}}))');
  assert.match(out, /"a": \{"b": 1\}/);
  assert.match(out, /"c": \[2, 3]/);
});

test('operators convert on every line of a multi-line statement', () => {
  // The continuation buffer converts its head at push time AND at flush:
  // idempotence (already-quoted dict keys survive) plus real conversion of
  // `..`/`~=`/`nil` sitting on line 2+ (previously emitted verbatim Python).
  const out = py('httpPost(url, jsonEncode({a = 1}),\n  {["H"] = "tok" .. id})');
  assert.match(out, /jsonEncode\(\{"a": 1\}\)/);
  assert.match(out, /\{"H": zxConcat\("tok", id\)\}/);
  assertLooksLikePython(out);
});

// ---------------------------------------------------------------- concat semantics

test('pure string concat also routes through zxConcat', () => {
  const out = py('log("a" .. "b")');
  assert.match(out, /zxConcat\("a", "b"\)/);
  assertLooksLikePython(out);
});

test('concat binds tighter than comparison', () => {
  const out = py('if "x" .. y == name then tap(1, 2) end');
  assert.match(out, /if zxConcat\("x", y\) == name:/);
  assertLooksLikePython(out);
});

test('arith operand keeps the whole expression', () => {
  const out = py('log("n=" .. i + 1)');
  assert.match(out, /zxConcat\("n=", i \+ 1\)/);
});

test('vararg dots are untouched', () => {
  const out = py('local t = {1, ...}');
  assert.match(out, /t = \[1, ...\]/);
});

// ---------------------------------------------------------------- existing behaviour (anti-regression)

test('string literal in condition still works (v0.3.6 fix)', () => {
  const out = py('if s ~= "" then log(s) end');
  assert.match(out, /if s != "":/);
});

test('multi-value local from httpGet keeps the .status rewrite', () => {
  const out = py('local body, status = httpGet("https://api.ipify.org")');
  assert.match(out, /^body = httpGet\("https:\/\/api\.ipify\.org"\); status = body\.status$/m);
});

test('multi-line table arguments convert as one unit', () => {
  const out = py('httpGet(url, {\n  ["Authorization"] = "Bearer t",\n  ["X-Id"] = 7\n})');
  assert.match(out, /\{"Authorization": "Bearer t", "X-Id": 7\}/);
  assertLooksLikePython(out);
});

test('ipairs/pairs loops translate', () => {
  assert.match(py('for _, v in ipairs(t) do\n  log(v)\nend'), /for _, v in enumerate\(t\):/);
  assert.match(py('for k, v in pairs(t) do\n  log(k)\nend'), /for k, v in t\.items\(\):/);
  // single-variable pairs() iterates keys, like Lua
  assert.match(py('for k in pairs(t) do\n  log(k)\nend'), /for k in t:/);
});

test('unsupported constructs still report the failing line', () => {
  assert.throws(() => py('repeat\n  log(1)\nuntil x'), (e) => e.line === 1 && /repeat/.test(e.message));
  assert.throws(() => py('log(1)\nend'), (e) => e.line === 2 && /unexpected/.test(e.message));
});

test('len operator and boolean keywords convert', () => {
  const out = py('if #list > 0 and flag == true then log("go") end');
  assert.match(out, /if len\(list\) > 0 and flag == True:/);
});

test('local x, y (no initializer) defaults both to None', () => {
  const out = py('local x, y');
  assert.equal(out, 'x = None; y = None');
});

// ------------------------------------------------- emitted-code syntax gate
// Golden strings catch semantic drift; this catches outright breakage: every
// transpiled snippet must parse as Python. Uses whatever interpreter exists
// (CI runners have python3, dev boxes 'python'); skips when none is found.
const PY_SNIPPETS = [
  'tap(200, 300)\nsleep(0.5)\nlog("done")',
  'local config = jsonDecode(raw)\nlog("Loops: " .. config.loops)\nlog("Delay: " .. config.delay .. "s")',
  'local s = screenSize()\nlog("Screen: " .. s.width .. "x" .. s.height)',
  'local ok, x, y = tapImage("btn.png")\nif ok then log("Tapped at " .. x .. "," .. y) end',
  'local ok, x, y = swipeUntilImage("target.png", "up", 15)\nif ok then tap(x, y) end',
  'local x, y = findImage("a.png",\n  0.9)\ntap(x, y)',
  'for i = 10, 1, -1 do\n  log(i)\nend',
  'for i = 10, 1, s do\n  log(i)\nend',
  'for i = 1, 10, 2 do\n  log(i)\nend',
  'for k, v in pairs(cfg) do\n  log(k .. "=" .. tostring(v))\nend',
  'for _, v in ipairs(list) do\n  log(v)\nend',
  'local t = {}\nfor i = 1, 3 do t[i] = i * 2 end\nlog(#t)',
  'httpGet("https://x", {["Authorization"] = "Bearer " .. token})',
  'if x >= 10 and y ~= nil then\n  log("big")\nelseif x > 5 then\n  log("mid")\nelse\n  log("small")\nend',
  'if "a" then log("truthy") end',
  'while running do\n  tapText("OK")\n  sleep(1)\nend',
  'local pts = findColor(0xFF0000, 5, {0, 0, 400, 400}, 10)\nif #pts > 0 then tap(pts[1][1], pts[1][2]) end',
  'local sum = 0\nfor i = 1, 100 do sum = sum + i end\nlog("sum = " .. sum)',
  'local body, status = httpGet("https://api.ipify.org")\nlog(body .. status)',
  'local r = jsonEncode({a = 1, b = {2, 3}})',
  'log("a" .. "b")',
  'touchDown(1, 100, 200)\ntouchUp(1, 100, 200)',
  'if x ~= "" then log(x .. "!") end',
];

test('every transpiled snippet parses as valid Python', (t) => {
  let python = null;
  for (const exe of ['python', 'python3']) {
    try { execFileSync(exe, ['--version'], { stdio: 'ignore' }); python = exe; break; }
    catch { /* try next */ }
  }
  if (!python) { t.skip('no python interpreter on PATH'); return; }
  for (const snippet of PY_SNIPPETS) {
    const out = py(snippet);
    try {
      execFileSync(python, ['-c', 'import sys, ast; ast.parse(sys.stdin.read())'],
        { input: out, stdio: ['pipe', 'ignore', 'pipe'] });
    } catch (e) {
      const err = (e.stderr ? e.stderr.toString() : '').split('\n').filter(Boolean).pop() || e.message;
      assert.fail(`emitted Python is invalid for ${JSON.stringify(snippet)}:\n${out}\n  -> ${err}`);
    }
  }
});

// ---------------------------------------------------------------- shipping parity

test('staged app dashboard carries the identical transpiler', () => {
  let staged;
  try { staged = readFileSync(STAGED, 'utf8'); }
  catch { return; } // layout/ is not checked out on every working copy
  assert.equal(extractTranspiler(staged), extractTranspiler(src),
    'layout/Applications/zxtouch.app/index.html must carry the same transpileLuaEx()');
});

// ---------------------------------------------------------------- line map

test('lineMap maps every emitted line back to its Lua source line', () => {
  const result = transpileLuaEx('tap(200, 300)\n\nlog("done")');
  assert.equal(result.lineMap.length, result.code.split('\n').length,
    'lineMap must have one entry per emitted line');
  assert.deepEqual(result.lineMap, [1, 2, 3]);
});

test('lineMap survives block openers, closers and blank lines', () => {
  const lua = 'for i = 1, 3 do\n  log(i)\nend\n\nlog("after")';
  const result = transpileLuaEx(lua);
  const out = result.code.split('\n');
  // "end" emits nothing, so the closing line is dropped from the map.
  assert.equal(out.length, result.lineMap.length);
  assert.equal(result.lineMap[0], 1);            // for header
  assert.equal(result.lineMap[1], 2);            // body
  assert.equal(result.lineMap[out.length - 1], 5); // trailing log()
  assert.ok(!result.lineMap.includes(3), '"end" must not own an emitted line');
});

test('lineMap maps the head of a multi-line statement to its first line', () => {
  const result = transpileLuaEx('httpGet(url, {\n  ["Authorization"] = "Bearer t"\n})');
  assert.equal(result.lineMap[0], 1);
  assert.equal(result.lineMap.length, result.code.split('\n').length);
});

test('one-line compound maps both emitted lines to the same source line', () => {
  const result = transpileLuaEx('if x then log(1); log(2) end');
  assert.equal(result.lineMap.length, result.code.split('\n').length);
  assert.ok(result.lineMap.every(line => line === 1));
});
