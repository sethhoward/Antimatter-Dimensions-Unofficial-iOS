// Browser API shims for JavaScriptCore
// Loaded by Swift BEFORE the game bundle — establishes the browser-like environment.
// Timers (setInterval, setTimeout) are registered from Swift, not here.
// _nativeLog is registered from Swift before this file runs.

// process.env — webpack replaces VUE_APP_* at build time, but provide a fallback
// in case any runtime code still references process.
globalThis.process = {
  env: {
    NODE_ENV: "production",
    VUE_APP_DEV: "false",
    VUE_APP_STEAM: "false",
  }
};

// GlobalErrorHandler — game.js references this at module level (lines 14-17).
// Must be defined before the bundle runs so the require() doesn't throw.
globalThis.NotImplementedError = class NotImplementedError extends Error {
  constructor() {
    super("Not implemented.");
    this.name = "NotImplementedError";
  }
};

globalThis.GlobalErrorHandler = {
  handled: false,
  cleanStart: false,
  onerror(event) {
    if (this.handled) return;
    this.handled = true;
    if (typeof _nativeLog === "function") _nativeLog("[crash] " + String(event));
  },
  stopGame() {},
  crash(message) {
    if (typeof _nativeLog === "function") _nativeLog("[crash] " + String(message));
  }
};

// window.onerror shim — crash.js sets this; no-op in JSCore
globalThis.onerror = () => {};

globalThis.getSelection = () => ({ removeAllRanges: () => {}, addRange: () => {} });
globalThis.window = globalThis;
globalThis.self = globalThis;

// (AutomatorTextUI / BlockAutomator stubs are defined later in this file)

globalThis.document = {
  getElementById: () => ({
    style: { display: "" },
    classList: Object.assign([], { add() {}, remove() {}, contains() { return false; }, toggle() {} }),
    appendChild: () => {},
    removeChild: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    setAttribute: () => {},
    getAttribute: () => null,
    innerHTML: "",
    textContent: "",
  }),
  createElement: () => ({
    style: {},
    classList: Object.assign([], { add() {}, remove() {}, contains() { return false; }, toggle() {} }),
    appendChild: () => {},
    removeChild: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    setAttribute: () => {},
    removeAttribute: () => {},
    getAttribute: () => null,
    hasAttribute: () => false,
    innerHTML: "",
    textContent: "",
    value: "",
    checked: false,
    disabled: false,
    children: [],
    childNodes: [],
  }),
  createTextNode: () => ({}),
  querySelector: () => null,
  querySelectorAll: () => [],
  addEventListener: () => {},
  removeEventListener: () => {},
  body: {
    style: {},
    appendChild: () => {},
    removeChild: () => {},
    classList: Object.assign([], { add() {}, remove() {}, contains() { return false; }, toggle() {} }),
  },
  head: { appendChild: () => {} },
  documentElement: { style: {} },
};

globalThis.navigator = {
  userAgent: "AntimatteriPad/1.0",
  maxTouchPoints: 5,
  msMaxTouchPoints: 0,
  platform: "iPad",
};

globalThis.performance = {
  now: () => Date.now(),
};

globalThis.HTMLElement = function HTMLElement() {};
globalThis.DocumentTouch = undefined;

// requestAnimationFrame via setTimeout shim (timers registered from Swift)
globalThis.requestAnimationFrame = fn => setTimeout(fn, 16);
globalThis.cancelAnimationFrame = id => clearTimeout(id);

// fetch — stub, returns empty responses; cloud saving is disabled
globalThis.fetch = () => Promise.resolve({
  ok: true,
  json: () => Promise.resolve({}),
  text: () => Promise.resolve(""),
});

// console — bridge to Swift's _nativeLog
globalThis.console = {
  log: (...args) => {
    if (typeof _nativeLog === "function") _nativeLog(args.map(a => String(a)).join(" "));
  },
  warn: (...args) => {
    if (typeof _nativeLog === "function") _nativeLog("[warn] " + args.map(a => String(a)).join(" "));
  },
  error: (...args) => {
    if (typeof _nativeLog === "function") {
      _nativeLog("[error] " + args.map(a => {
        if (a instanceof Error) return a.message + "\n" + (a.stack || "");
        return String(a);
      }).join(" "));
    }
  },
  info: (...args) => {
    if (typeof _nativeLog === "function") _nativeLog("[info] " + args.map(a => String(a)).join(" "));
  },
  debug: () => {},
  group: () => {},
  groupEnd: () => {},
  groupCollapsed: () => {},
  time: () => {},
  timeEnd: () => {},
};

// TextEncoder / TextDecoder — JSCore doesn't have these; used by save encoding
globalThis.TextEncoder = class TextEncoder {
  encode(str) {
    const buf = [];
    for (let i = 0; i < str.length; i++) {
      let c = str.charCodeAt(i);
      if (c < 0x80) buf.push(c);
      else if (c < 0x800) { buf.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f)); }
      else if (c < 0xd800 || c >= 0xe000) { buf.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f)); }
      else { i++; c = 0x10000 + (((c & 0x3ff) << 10) | (str.charCodeAt(i) & 0x3ff)); buf.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 0x3f), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f)); }
    }
    return new Uint8Array(buf);
  }
};

globalThis.TextDecoder = class TextDecoder {
  decode(buf) {
    const bytes = new Uint8Array(buf);
    let str = "", i = 0;
    while (i < bytes.length) {
      let c = bytes[i++];
      if (c < 0x80) { str += String.fromCharCode(c); }
      else if (c < 0xe0) { str += String.fromCharCode(((c & 0x1f) << 6) | (bytes[i++] & 0x3f)); }
      else if (c < 0xf0) { const c2 = bytes[i++]; str += String.fromCharCode(((c & 0x0f) << 12) | ((c2 & 0x3f) << 6) | (bytes[i++] & 0x3f)); }
      else { const c2 = bytes[i++], c3 = bytes[i++]; const cp = ((c & 0x07) << 18) | ((c2 & 0x3f) << 12) | ((c3 & 0x3f) << 6) | (bytes[i++] & 0x3f); str += String.fromCodePoint(cp); }
    }
    return str;
  }
};

// PerkNetwork — defined in PerksTab.vue, referenced by themes.js and reality.js
globalThis.PerkNetwork = {
  forceNetworkRemake: () => {},
  updatePerkColor: () => {},
  network: { body: { nodes: {} } },
};

// CodeMirror global — automator files reference it; shims.js normally sets window.CodeMirror
globalThis.CodeMirror = {
  registerHelper: () => {},
  defineMode: () => {},
  defineMIME: () => {},
  defineSimpleMode: () => {},
};

// AutomatorTextUI / BlockAutomator — Vue component refs used by automator-backend.js;
// must exist as no-ops so save import and automator state transitions don't crash.
// editor stub covers: scrollToLine, line highlighting, undo/redo, script conversion.
var _cmEditorStub = {
  defaultTextHeight: function() { return 14; },
  getDoc: function() { return { getValue: function() { return ""; }, size: 0 }; },
  doc: { size: 0 },
  setValue: function() {},
  addLineClass: function() {},
  removeLineClass: function() {},
};
globalThis.AutomatorTextUI = {
  editor: _cmEditorStub,
  clearEditor: () => {},
};
globalThis.BlockAutomator = {
  editor: null,
  lines: [],
  parseLines: () => [],
  parseTextFromBlocks: () => {},
  updateEditor: () => {},
  clearEditor: () => {},
  gutter: { style: {} },
  lineNumber: () => 0,
};

// btoa / atob — JSCore doesn't provide these; used by save encoding
globalThis.btoa = function(str) {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
  let output = "";
  for (let i = 0; i < str.length; i += 3) {
    const a = str.charCodeAt(i);
    const b = i + 1 < str.length ? str.charCodeAt(i + 1) : 0;
    const c = i + 2 < str.length ? str.charCodeAt(i + 2) : 0;
    output += chars[a >> 2] + chars[((a & 3) << 4) | (b >> 4)];
    output += i + 1 < str.length ? chars[((b & 15) << 2) | (c >> 6)] : "=";
    output += i + 2 < str.length ? chars[c & 63] : "=";
  }
  return output;
};

globalThis.atob = function(str) {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
  let output = "";
  str = str.replace(/=+$/, "");
  for (let i = 0; i < str.length; i += 4) {
    const a = chars.indexOf(str[i]);
    const b = chars.indexOf(str[i + 1]);
    const c = chars.indexOf(str[i + 2]);
    const d = chars.indexOf(str[i + 3]);
    output += String.fromCharCode((a << 2) | (b >> 4));
    if (c !== -1) output += String.fromCharCode(((b & 15) << 4) | (c >> 2));
    if (d !== -1) output += String.fromCharCode(((c & 3) << 6) | d);
  }
  return output;
};

// location — needed by some libraries
globalThis.location = {
  href: "file://antimatter",
  hostname: "localhost",
  protocol: "file:",
  search: "",
  hash: "",
};

// ═══════════════════════════════════════════════════════════════════════════════
// Decimal performance patches — called by Swift after bundle load, before init()
// Adds native-number fast paths to break_infinity.js prototype methods to
// eliminate ~200-300 unnecessary Decimal allocations per game tick.
// ═══════════════════════════════════════════════════════════════════════════════
globalThis._patchDecimalPerf = function() {
  var Decimal = globalThis.Decimal;
  if (!Decimal || !Decimal.prototype) return;

  // Capture original implementations BEFORE patching so the divergence harness
  // (DEBUG-only, see _installDecimalDivergenceHarness below) can compare patched
  // vs original results without paying any production cost. timesEffectsOf is
  // saved separately by the Swift-injected patch in GameEngine.swift.
  globalThis._origDecimalMethods = globalThis._origDecimalMethods || {};
  var _proto = Decimal.prototype;
  var _protoNames = ["cmp","lt","gt","lte","gte","eq","add","sub","div","mul",
                     "pow","recip","sqr","abs","neg","clampMin","clampMax",
                     "clamp","sqrt","max","min","plus","subtract","minus",
                     "divide","divideBy","dividedBy","multiply","times",
                     "reciprocal","reciprocate","negate","negated"];
  for (var _pi = 0; _pi < _protoNames.length; _pi++) {
    var _pn = _protoNames[_pi];
    if (typeof _proto[_pn] === "function" && globalThis._origDecimalMethods[_pn] === undefined) {
      globalThis._origDecimalMethods[_pn] = _proto[_pn];
    }
  }
  var _staticNames = ["log10","absLog10","pLog10","log","abs","neg","sqrt",
                      "add","sub","mul","max","min","plus","subtract","minus",
                      "multiply","times","negate","negated"];
  for (var _si = 0; _si < _staticNames.length; _si++) {
    var _sn = _staticNames[_si];
    if (typeof Decimal[_sn] === "function" && globalThis._origDecimalMethods["s_"+_sn] === undefined) {
      globalThis._origDecimalMethods["s_"+_sn] = Decimal[_sn];
    }
  }

  // Recreate the powerOf10 lookup table (original is a closure we can't access)
  var _powersOf10 = [];
  for (var i = -323; i <= 308; i++) _powersOf10.push(Number("1e" + i));
  function _p10(power) { return _powersOf10[power + 323]; }

  // Helper: decompose a JS number into mantissa + exponent without allocating a Decimal.
  // Matches fromNumber() logic exactly for behavioral parity.
  var NUMBER_EXP_MIN = -324;
  function _numToME(value) {
    // Returns [mantissa, exponent]. Only called for finite, non-zero, non-NaN numbers.
    var e = Math.floor(Math.log10(Math.abs(value)));
    var m = e === NUMBER_EXP_MIN ? value * 10 / 1e-323 : value / _p10(e);
    // Inline normalize (same as Decimal.prototype.normalize)
    if (m >= 1 && m < 10) return [m, e];
    if (m <= -1 && m > -10) return [m, e];
    var te = Math.floor(Math.log10(Math.abs(m)));
    m = te === NUMBER_EXP_MIN ? m * 10 / 1e-323 : m / _p10(te);
    return [m, e + te];
  }

  // ── Comparison: cmp() ─────────────────────────────────────────────────────
  var _origCmp = Decimal.prototype.cmp;
  Decimal.prototype.cmp = function(value) {
    if (typeof value === "number") {
      if (value === 0) {
        if (this.mantissa === 0) return 0;
        return this.mantissa > 0 ? 1 : -1;
      }
      if (this.mantissa === 0) return value > 0 ? -1 : 1;
      // Sign mismatch — quick exit
      if (this.mantissa > 0 && value < 0) return 1;
      if (this.mantissa < 0 && value > 0) return -1;
      // Decompose value to mantissa+exponent without allocation
      var me = _numToME(value);
      if (this.mantissa > 0) {
        if (this.exponent > me[1]) return 1;
        if (this.exponent < me[1]) return -1;
        if (this.mantissa > me[0]) return 1;
        if (this.mantissa < me[0]) return -1;
        return 0;
      }
      // Both negative
      if (this.exponent > me[1]) return -1;
      if (this.exponent < me[1]) return 1;
      if (this.mantissa > me[0]) return 1;
      if (this.mantissa < me[0]) return -1;
      return 0;
    }
    return _origCmp.call(this, value);
  };

  // ── Comparison: lt, gt, lte, gte, eq ──────────────────────────────────────
  var _origLt = Decimal.prototype.lt;
  Decimal.prototype.lt = function(value) {
    if (typeof value === "number") return this.cmp(value) < 0;
    return _origLt.call(this, value);
  };

  var _origGt = Decimal.prototype.gt;
  Decimal.prototype.gt = function(value) {
    if (typeof value === "number") return this.cmp(value) > 0;
    return _origGt.call(this, value);
  };

  Decimal.prototype.lte = function(value) { return !this.gt(value); };
  Decimal.prototype.gte = function(value) { return !this.lt(value); };

  var _origEq = Decimal.prototype.eq;
  Decimal.prototype.eq = function(value) {
    if (typeof value === "number") {
      if (value === 0) return this.mantissa === 0;
      if (this.mantissa === 0) return false;
      var me = _numToME(value);
      return this.exponent === me[1] && this.mantissa === me[0];
    }
    return _origEq.call(this, value);
  };

  // ── max / min — avoid D() allocation for numbers ──────────────────────────
  Decimal.prototype.max = function(value) {
    if (typeof value === "number") {
      return this.cmp(value) < 0 ? new Decimal(value) : this;
    }
    var decimal = value instanceof Decimal ? value : new Decimal(value);
    return this.lt(decimal) ? decimal : this;
  };

  Decimal.prototype.min = function(value) {
    if (typeof value === "number") {
      return this.cmp(value) > 0 ? new Decimal(value) : this;
    }
    var decimal = value instanceof Decimal ? value : new Decimal(value);
    return this.gt(decimal) ? decimal : this;
  };

  // ── add() — number fast path ──────────────────────────────────────────────
  var _origAdd = Decimal.prototype.add;
  Decimal.prototype.add = function(value) {
    if (typeof value === "number") {
      if (value === 0) return this;
      if (this.mantissa === 0) return new Decimal(value);
      // Decompose number inline instead of D(value)
      var me = _numToME(value);
      var bigM, bigE, smallM, smallE;
      if (this.exponent >= me[1]) {
        bigM = this.mantissa; bigE = this.exponent;
        smallM = me[0]; smallE = me[1];
      } else {
        bigM = me[0]; bigE = me[1];
        smallM = this.mantissa; smallE = this.exponent;
      }
      if (bigE - smallE > 17) {
        // Small value is insignificant
        return bigE === this.exponent ? this : new Decimal(value);
      }
      var mantissa = Math.round(1e14 * bigM + 1e14 * smallM * _p10(smallE - bigE));
      return Decimal.fromMantissaExponent(mantissa, bigE - 14);
    }
    return _origAdd.call(this, value);
  };

  Decimal.prototype.plus = Decimal.prototype.add;

  // ── sub() — inline negation, skip D()+neg() ──────────────────────────────
  Decimal.prototype.sub = function(value) {
    if (typeof value === "number") return this.add(-value);
    if (value instanceof Decimal) {
      // Inline the negation: add with negated mantissa instead of creating neg() intermediate
      if (value.mantissa === 0) return this;
      if (this.mantissa === 0) {
        return new Decimal().fromMantissaExponent_noNormalize(-value.mantissa, value.exponent);
      }
      var bigM, bigE, smallM, smallE;
      if (this.exponent >= value.exponent) {
        bigM = this.mantissa; bigE = this.exponent;
        smallM = -value.mantissa; smallE = value.exponent;
      } else {
        bigM = -value.mantissa; bigE = value.exponent;
        smallM = this.mantissa; smallE = this.exponent;
      }
      if (bigE - smallE > 17) {
        if (bigE === this.exponent) return this;
        return new Decimal().fromMantissaExponent_noNormalize(-value.mantissa, value.exponent);
      }
      var mantissa = Math.round(1e14 * bigM + 1e14 * smallM * _p10(smallE - bigE));
      return Decimal.fromMantissaExponent(mantissa, bigE - 14);
    }
    return this.add(new Decimal(value).neg());
  };

  Decimal.prototype.subtract = Decimal.prototype.sub;
  Decimal.prototype.minus = Decimal.prototype.sub;

  // ── div() — skip recip() intermediate ─────────────────────────────────────
  Decimal.prototype.div = function(value) {
    if (typeof value === "number") {
      // Direct division for numbers — one allocation instead of D()+recip()+mul()
      if (value < 1e307 && value > -1e307) {
        return Decimal.fromMantissaExponent(this.mantissa / value, this.exponent);
      }
      return Decimal.fromMantissaExponent(this.mantissa / (value * 1e-307), this.exponent - 307);
    }
    if (value instanceof Decimal) {
      // Direct: one allocation instead of recip()+mul()
      return Decimal.fromMantissaExponent(this.mantissa / value.mantissa, this.exponent - value.exponent);
    }
    var decimal = new Decimal(value);
    return Decimal.fromMantissaExponent(this.mantissa / decimal.mantissa, this.exponent - decimal.exponent);
  };

  Decimal.prototype.divide = Decimal.prototype.div;
  Decimal.prototype.divideBy = Decimal.prototype.div;
  Decimal.prototype.dividedBy = Decimal.prototype.div;

  // ── pow() — fast paths for common exponent patterns ────────────────────────
  // pow() is the single hottest unpatched method (~100-150 calls/tick).
  // The original always converts to number, does log/exp math, and may call
  // Decimal.pow10() as fallback (creating another allocation). We add:
  //   - pow(0) → 1, pow(1) → this (trivial)
  //   - pow(number) → inline the same math but skip D(value) conversion
  var _origPow = Decimal.prototype.pow;
  Decimal.prototype.pow = function(value) {
    // Number fast path (most common case — called with plain numbers for multipliers)
    if (typeof value === "number") {
      if (value === 0) return new Decimal().fromMantissaExponent_noNormalize(1, 0);
      if (value === 1) return this;
      if (this.mantissa === 0) return this; // 0^anything = 0 (value > 0 in game)
      if (this.mantissa === 1 && this.exponent === 0) return this; // 1^anything = 1

      // Fast track: if e*value is safe integer and mantissa^value fits in a Number
      var temp = this.exponent * value;
      if (Number.isSafeInteger(temp)) {
        var newMantissa = Math.pow(this.mantissa, value);
        if (isFinite(newMantissa) && newMantissa !== 0) {
          return Decimal.fromMantissaExponent(newMantissa, temp);
        }
      }
      // General case: inline log/exp path (same math as original, no D() allocation)
      var newExponent = Math.trunc(temp);
      var residue = temp - newExponent;
      var newM = Math.pow(10, value * Math.log10(this.mantissa) + residue);
      if (isFinite(newM) && newM !== 0) {
        return Decimal.fromMantissaExponent(newM, newExponent);
      }
      // Fallback to pow10 path
      var result = Decimal.pow10(value * this.absLog10());
      if (this.mantissa < 0) {
        if (Math.abs(value % 2) === 1) return result.neg();
        if (Math.abs(value % 2) === 0) return result;
        return new Decimal(Number.NaN);
      }
      return result;
    }
    return _origPow.call(this, value);
  };

  // ── pow10() — static factory, avoid allocation for integer exponents ──────
  // Called ~50-80×/tick. Original already has fast path for integers but
  // uses ME_NN (closure-scoped). We replace with direct construction.
  var _origPow10 = Decimal.pow10;
  Decimal.pow10 = function(value) {
    if (Number.isInteger(value)) {
      return new Decimal().fromMantissaExponent_noNormalize(1, value);
    }
    return new Decimal().fromMantissaExponent(Math.pow(10, value % 1), Math.trunc(value));
  };

  // ── Decimal.pow() static — fast track for 10^integer ──────────────────────
  var _origStaticPow = Decimal.pow;
  Decimal.pow = function(value, other) {
    if (typeof value === "number" && value === 10 && typeof other === "number" && Number.isInteger(other)) {
      return new Decimal().fromMantissaExponent_noNormalize(1, other);
    }
    return new Decimal(value).pow(other);
  };

  // ── floor() / ceil() / round() — skip allocation for large/small values ──
  // Called ~20-30×/tick. For large exponents (e >= 17), the number has no
  // fractional part — return this without allocation.
  var _origFloor = Decimal.prototype.floor;
  Decimal.prototype.floor = function() {
    if (this.exponent >= 17) return this; // MAX_SIGNIFICANT_DIGITS = 17
    if (this.exponent < -1) {
      return this.mantissa >= 0
        ? new Decimal().fromMantissaExponent_noNormalize(0, 0)
        : new Decimal().fromMantissaExponent_noNormalize(-1, 0);
    }
    return new Decimal(Math.floor(this.toNumber()));
  };

  var _origCeil = Decimal.prototype.ceil;
  Decimal.prototype.ceil = function() {
    if (this.exponent >= 17) return this;
    if (this.exponent < -1) {
      return this.mantissa > 0
        ? new Decimal().fromMantissaExponent_noNormalize(1, 0)
        : new Decimal().fromMantissaExponent_noNormalize(0, 0);
    }
    return new Decimal(Math.ceil(this.toNumber()));
  };

  var _origRound = Decimal.prototype.round;
  Decimal.prototype.round = function() {
    if (this.exponent >= 17) return this;
    if (this.exponent < -1) return new Decimal(Math.round(this.toNumber()));
    return new Decimal(Math.round(this.toNumber()));
  };

  // ── Static Decimal.floor/ceil — avoid D() for plain numbers ───────────────
  Decimal.floor = function(value) {
    if (typeof value === "number") return new Decimal(Math.floor(value));
    return new Decimal(value).floor();
  };

  Decimal.ceil = function(value) {
    if (typeof value === "number") return new Decimal(Math.ceil(value));
    return new Decimal(value).ceil();
  };

  Decimal.round = function(value) {
    if (typeof value === "number") return new Decimal(Math.round(value));
    return new Decimal(value).round();
  };

  // ── times() / mul() — number fast path ────────────────────────────────────
  // Multiplication is the single most common operation (~220+ calls/tick).
  // The original always calls D(value) for non-Decimal inputs.
  var _origMul = Decimal.prototype.mul;
  Decimal.prototype.mul = function(value) {
    if (typeof value === "number") {
      if (value === 0 || this.mantissa === 0) return new Decimal().fromMantissaExponent_noNormalize(0, 0);
      if (value === 1) return this;
      if (value === -1) return new Decimal().fromMantissaExponent_noNormalize(-this.mantissa, this.exponent);
      if (value === 10) return Decimal.fromMantissaExponent(this.mantissa, this.exponent + 1);
      // General: decompose number, multiply mantissas, add exponents
      var me = _numToME(value);
      return Decimal.fromMantissaExponent(this.mantissa * me[0], this.exponent + me[1]);
    }
    return _origMul.call(this, value);
  };
  Decimal.prototype.multiply = Decimal.prototype.mul;
  Decimal.prototype.times = Decimal.prototype.mul;

  // ── Pre-allocated constants ───────────────────────────────────────────────
  // Frequently created values cached to avoid repeated allocation.
  Decimal._CACHED_ZERO = new Decimal().fromMantissaExponent_noNormalize(0, 0);
  Decimal._CACHED_ONE = new Decimal().fromMantissaExponent_noNormalize(1, 0);

  // ═══════════════════════════════════════════════════════════════════════════
  // Phase 3: New method patches
  // Patches for methods not covered in Phase 1/2. Does NOT re-patch
  // mul/div/add/sub/pow — those Phase 1/2 versions are already JIT-hot.
  // ═══════════════════════════════════════════════════════════════════════════

  // ── abs() — return this when already positive ────────────────────────────
  Decimal.prototype.abs = function() {
    if (this.mantissa >= 0) return this;
    return new Decimal().fromMantissaExponent_noNormalize(-this.mantissa, this.exponent);
  };

  // ── neg() — skip allocation, just flip sign ───────────────────────────────
  Decimal.prototype.neg = function() {
    if (this.mantissa === 0) return this; // -0 === 0, return same object
    return new Decimal().fromMantissaExponent_noNormalize(-this.mantissa, this.exponent);
  };
  Decimal.prototype.negate = Decimal.prototype.neg;
  Decimal.prototype.negated = Decimal.prototype.neg;

  // ── clampMin / clampMax — number fast path, return this when in range ────
  Decimal.prototype.clampMin = function(min) {
    if (typeof min === "number") return this.cmp(min) >= 0 ? this : new Decimal(min);
    var decimal = min instanceof Decimal ? min : new Decimal(min);
    return this.lt(decimal) ? decimal : this;
  };
  Decimal.prototype.clampMax = function(max) {
    if (typeof max === "number") return this.cmp(max) <= 0 ? this : new Decimal(max);
    var decimal = max instanceof Decimal ? max : new Decimal(max);
    return this.gt(decimal) ? decimal : this;
  };
  Decimal.prototype.clamp = function(min, max) {
    return this.clampMin(min).clampMax(max);
  };

  // ── sqrt() — inline normalization ────────────────────────────────────────
  Decimal.prototype.sqrt = function() {
    if (this.mantissa < 0) return new Decimal(Number.NaN);
    if (this.mantissa === 0) return this; // sqrt(0) = 0, return same object
    var newM, newE;
    if (this.exponent % 2 !== 0) {
      // sqrt([1,10) * sqrt(10)) = [sqrt(10), 10) ≈ [3.162, 10) — normalized
      newM = Math.sqrt(this.mantissa) * 3.16227766016838;
      newE = Math.floor(this.exponent / 2);
    } else {
      // sqrt([1,10)) = [1, sqrt(10)) ≈ [1, 3.162) — normalized
      newM = Math.sqrt(this.mantissa);
      newE = Math.floor(this.exponent / 2);
    }
    return new Decimal().fromMantissaExponent_noNormalize(newM, newE);
  };

  // ── recip() — inline normalization ───────────────────────────────────────
  Decimal.prototype.recip = function() {
    // break_infinity's recip is `fromMantissaExponent(1/m, -e)`. That function
    // hits its `!isFinite` else-branch on non-finite inputs and returns the
    // default `{m:0, e:0}` (zero) — never NaN. Mirror that defensive contract,
    // otherwise reciprocating zero / a NaN-decimal poisons every downstream
    // chain with NaN. Confirmed call site is display-only (`pollGlyphs` →
    // `cfg.formatEffect(0)` → notation `recip` for one tick post-eternity
    // while the underlying effect value briefly transitions through 0).
    if (this.mantissa === 0 || !isFinite(this.mantissa) || !isFinite(this.exponent)) {
      return new Decimal(0);
    }
    // 1/[1,10) = (0.1, 1] → *10 gives [1,10) — already normalized
    var newM = 10 / this.mantissa;
    // newM is in [1, 10) for positive mantissa, (-10, -1] for negative
    return new Decimal().fromMantissaExponent_noNormalize(newM, -this.exponent - 1);
  };
  Decimal.prototype.reciprocal = Decimal.prototype.recip;
  Decimal.prototype.reciprocate = Decimal.prototype.recip;

  // ── sqr() — inline normalization ─────────────────────────────────────────
  Decimal.prototype.sqr = function() {
    // mantissa in [1,10) → product in [1,100), exponent doubles
    var m2 = this.mantissa * this.mantissa;
    if (m2 >= 10) return new Decimal().fromMantissaExponent_noNormalize(m2 / 10, this.exponent * 2 + 1);
    return new Decimal().fromMantissaExponent_noNormalize(m2, this.exponent * 2);
  };

  // ── Static method number fast paths ──────────────────────────────────────
  // All static methods call D(value) which creates new Decimal(value) for
  // numbers. Add fast paths that skip the allocation.

  Decimal.log10 = function(value) {
    if (typeof value === "number") return Math.log10(value);
    var d = value instanceof Decimal ? value : new Decimal(value);
    return d.log10();
  };

  Decimal.absLog10 = function(value) {
    if (typeof value === "number") return Math.abs(Math.log10(value));
    var d = value instanceof Decimal ? value : new Decimal(value);
    return d.absLog10();
  };

  Decimal.pLog10 = function(value) {
    if (typeof value === "number") return value <= 0 ? 0 : Math.log10(value);
    var d = value instanceof Decimal ? value : new Decimal(value);
    return d.pLog10();
  };

  Decimal.log = function(value, base) {
    if (typeof value === "number") return Math.log(value) / Math.log(base);
    var d = value instanceof Decimal ? value : new Decimal(value);
    return d.log(base);
  };

  Decimal.abs = function(value) {
    if (typeof value === "number") return new Decimal(Math.abs(value));
    var d = value instanceof Decimal ? value : new Decimal(value);
    return d.abs();
  };

  Decimal.neg = function(value) {
    if (typeof value === "number") return new Decimal(-value);
    var d = value instanceof Decimal ? value : new Decimal(value);
    return d.neg();
  };
  Decimal.negate = Decimal.neg;
  Decimal.negated = Decimal.neg;

  Decimal.sqrt = function(value) {
    if (typeof value === "number") {
      if (value < 0) return new Decimal(Number.NaN);
      return new Decimal(Math.sqrt(value));
    }
    var d = value instanceof Decimal ? value : new Decimal(value);
    return d.sqrt();
  };

  // Decimal.add / .mul / .max / .min — number first-arg fast path
  Decimal.add = function(value, other) {
    if (typeof value === "number") return new Decimal(value).add(other);
    var d = value instanceof Decimal ? value : new Decimal(value);
    return d.add(other);
  };
  Decimal.plus = Decimal.add;

  Decimal.sub = function(value, other) {
    if (typeof value === "number") return new Decimal(value).sub(other);
    var d = value instanceof Decimal ? value : new Decimal(value);
    return d.sub(other);
  };
  Decimal.subtract = Decimal.sub;
  Decimal.minus = Decimal.sub;

  Decimal.mul = function(value, other) {
    if (typeof value === "number") return new Decimal(value).mul(other);
    var d = value instanceof Decimal ? value : new Decimal(value);
    return d.mul(other);
  };
  Decimal.multiply = Decimal.mul;
  Decimal.times = Decimal.mul;

  Decimal.max = function(value, other) {
    if (typeof value === "number") {
      var otherD = other instanceof Decimal ? other : new Decimal(other);
      return otherD.cmp(value) > 0 ? otherD : new Decimal(value);
    }
    var d = value instanceof Decimal ? value : new Decimal(value);
    return d.max(other);
  };

  Decimal.min = function(value, other) {
    if (typeof value === "number") {
      var otherD = other instanceof Decimal ? other : new Decimal(other);
      return otherD.cmp(value) < 0 ? otherD : new Decimal(value);
    }
    var d = value instanceof Decimal ? value : new Decimal(value);
    return d.min(other);
  };

  if (typeof _nativeLog === "function") _nativeLog("[perf] Decimal prototype patched: Phase 1/2 (cmp,lt,gt,lte,gte,eq,max,min,add,sub,div,pow,pow10,floor,ceil,round,mul) + Phase 3 (abs,neg,clamp,sqrt,recip,sqr,statics). timesEffectsOf is patched separately by Swift at start() — see GameEngine.timesEffectsOfPatchSource.");
};

// ═══════════════════════════════════════════════════════════════════════════════
// Decimal divergence harness — DEBUG only.
// ═══════════════════════════════════════════════════════════════════════════════
// Wraps every patched Decimal method so 1-in-N calls also runs the original and
// logs any mismatch via _nativeLog. The patched result is always returned, so
// the harness can never alter gameplay — it only observes.
//
// Install AFTER _patchDecimalPerf and the Swift timesEffectsOf patch have both
// run, by calling _installDecimalDivergenceHarness(everyN). Idempotent: the
// harness wrap checks a flag and refuses to install twice.
//
// Comparison tolerates tiny FP drift (relative 1e-10, absolute 1e-12) because
// some patched paths (e.g. div using direct mantissa division instead of
// mul(recip())) accumulate one fewer rounding step. Anything larger is a real
// divergence and gets logged. Logs cap at 200 entries per install to avoid
// console flooding.
//
// Cost when not installed: zero (function is just defined, never called).
// Cost when installed: ~3 extra instructions per call (counter inc + modulo)
// plus the full comparison + original-method call on every Nth invocation.
// Default sampling rate of 50 means <2% throughput hit on hot paths.
// ═══════════════════════════════════════════════════════════════════════════════
globalThis._installDecimalDivergenceHarness = function(everyN) {
  if (globalThis._decimalDivergenceHarnessInstalled) {
    if (typeof _nativeLog === "function") _nativeLog("[decimal-harness] already installed, skipping");
    return;
  }
  var Decimal = globalThis.Decimal;
  var orig = globalThis._origDecimalMethods;
  if (!Decimal || !orig) {
    if (typeof _nativeLog === "function") _nativeLog("🔴 [decimal-harness] cannot install — _patchDecimalPerf must run first");
    return;
  }
  if (typeof everyN !== "number" || everyN < 1) everyN = 50;

  var counter = 0;
  var logBudget = 200;

  function fmt(v) {
    if (v === null || v === undefined) return String(v);
    var t = typeof v;
    if (t === "number") {
      if (isNaN(v)) return "NaN";
      if (!isFinite(v)) return v > 0 ? "+Inf" : "-Inf";
      return String(v);
    }
    if (t === "boolean" || t === "string") return String(v);
    if (t === "object" && "mantissa" in v && "exponent" in v) {
      return v.mantissa + "e" + v.exponent;
    }
    try { return String(v); } catch (e) { return "[unstringifiable]"; }
  }

  function fmtArgs(args) {
    var out = [];
    for (var i = 0; i < args.length; i++) out.push(fmt(args[i]));
    return out.join(", ");
  }

  function logMismatch(name, args, patchedRes, origRes, threwBoth) {
    if (logBudget <= 0) return;
    logBudget--;
    var msg = "🔴 [decimal-harness] " + name + "(" + fmtArgs(args) + ") " +
              "patched=" + fmt(patchedRes) + " original=" + fmt(origRes);
    if (threwBoth) msg += " (one threw)";
    // Capture call site. JSCore's Error.stack is comma-separated "func@url:line:col"
    // entries. Skip the first 3 frames (Error ctor / logMismatch / wrap closure)
    // and the trailing native frames; keep the next ~6 to reveal the caller chain.
    var stack;
    try { stack = (new Error()).stack || ""; } catch (e) { stack = ""; }
    if (stack) {
      var frames = stack.split("\n").map(function(s) { return s.trim(); }).filter(Boolean);
      frames = frames.slice(2, 10);
      if (frames.length) msg += "\n    " + frames.join("\n    ");
    }
    if (typeof _nativeLog === "function") _nativeLog(msg);
    if (logBudget === 0 && typeof _nativeLog === "function") {
      _nativeLog("[decimal-harness] log budget exhausted; further mismatches suppressed this session");
    }
  }

  function eqResult(a, b) {
    if (a === b) return true;
    if (a == null || b == null) return a == b;
    var ta = typeof a, tb = typeof b;
    if (ta !== tb) return false;
    if (ta === "number") {
      if (isNaN(a) && isNaN(b)) return true;
      if (!isFinite(a) || !isFinite(b)) return a === b;
      var d = Math.abs(a - b);
      if (d < 1e-12) return true;
      var mag = Math.max(Math.abs(a), Math.abs(b));
      return mag > 0 && d / mag < 1e-10;
    }
    if (ta === "boolean" || ta === "string") return a === b;
    if (ta === "object" && "mantissa" in a && "mantissa" in b) {
      // Zero handling — break_infinity treats m=0 as zero regardless of exponent.
      if (a.mantissa === 0 && b.mantissa === 0) return true;
      if (a.mantissa === 0 || b.mantissa === 0) return false;
      // Sign mismatch
      if ((a.mantissa < 0) !== (b.mantissa < 0)) return false;
      // Compare numeric value via total log10 instead of trying to reconstitute
      // via mantissa * 10^exponent — that path underflows to 0 in the subnormal
      // range (e.g. Math.pow(10, -406) === 0) and can't distinguish unnormalized
      // representations like {m:10, e:-406} from {m:1, e:-405} (same value).
      // log10(|v|) = log10(|mantissa|) + exponent — finite for any representable
      // break_infinity number, so this comparison works across the full range.
      var aLog = Math.log10(Math.abs(a.mantissa)) + a.exponent;
      var bLog = Math.log10(Math.abs(b.mantissa)) + b.exponent;
      if (aLog === bLog) return true;
      var logDiff = Math.abs(aLog - bLog);
      // 1e-10 in log10-space ≈ 2.3e-10 relative drift in linear value.
      // Use absolute tolerance when both are near zero in log-space.
      if (logDiff < 1e-12) return true;
      var logMag = Math.max(Math.abs(aLog), Math.abs(bLog));
      return logMag > 0 && logDiff / logMag < 1e-10;
    }
    return false;
  }

  function wrap(name, patched, original) {
    return function() {
      counter++;
      if (counter % everyN !== 0) {
        return patched.apply(this, arguments);
      }
      var pRes, oRes, pThrew = false, oThrew = false;
      try { pRes = patched.apply(this, arguments); }
      catch (e) { pThrew = true; pRes = e; }
      try { oRes = original.apply(this, arguments); }
      catch (e) { oThrew = true; oRes = e; }
      if (pThrew !== oThrew) {
        logMismatch(name, arguments, pRes, oRes, true);
      } else if (!pThrew && !eqResult(pRes, oRes)) {
        logMismatch(name, arguments, pRes, oRes, false);
      }
      if (pThrew) throw pRes;
      return pRes;
    };
  }

  var protoNames = ["cmp","lt","gt","lte","gte","eq","add","sub","div","mul",
                    "pow","recip","sqr","abs","neg","clampMin","clampMax",
                    "clamp","sqrt","max","min","timesEffectsOf"];
  for (var i = 0; i < protoNames.length; i++) {
    var n = protoNames[i];
    if (typeof orig[n] === "function" && typeof Decimal.prototype[n] === "function") {
      Decimal.prototype[n] = wrap(n, Decimal.prototype[n], orig[n]);
    }
  }
  // Aliases — re-point them to the (now-wrapped) canonical method so calls
  // through plus/minus/times/etc. also get sampled.
  if (Decimal.prototype.add) Decimal.prototype.plus = Decimal.prototype.add;
  if (Decimal.prototype.sub) {
    Decimal.prototype.subtract = Decimal.prototype.sub;
    Decimal.prototype.minus    = Decimal.prototype.sub;
  }
  if (Decimal.prototype.div) {
    Decimal.prototype.divide    = Decimal.prototype.div;
    Decimal.prototype.divideBy  = Decimal.prototype.div;
    Decimal.prototype.dividedBy = Decimal.prototype.div;
  }
  if (Decimal.prototype.mul) {
    Decimal.prototype.multiply = Decimal.prototype.mul;
    Decimal.prototype.times    = Decimal.prototype.mul;
  }
  if (Decimal.prototype.recip) {
    Decimal.prototype.reciprocal  = Decimal.prototype.recip;
    Decimal.prototype.reciprocate = Decimal.prototype.recip;
  }
  if (Decimal.prototype.neg) {
    Decimal.prototype.negate  = Decimal.prototype.neg;
    Decimal.prototype.negated = Decimal.prototype.neg;
  }

  var staticNames = ["log10","absLog10","pLog10","log","abs","neg","sqrt",
                     "add","sub","mul","max","min"];
  for (var j = 0; j < staticNames.length; j++) {
    var sn = staticNames[j];
    if (typeof orig["s_"+sn] === "function" && typeof Decimal[sn] === "function") {
      Decimal[sn] = wrap("Decimal." + sn, Decimal[sn], orig["s_"+sn]);
    }
  }
  if (Decimal.add)  Decimal.plus     = Decimal.add;
  if (Decimal.sub)  { Decimal.subtract = Decimal.sub; Decimal.minus = Decimal.sub; }
  if (Decimal.mul)  { Decimal.multiply = Decimal.mul; Decimal.times = Decimal.mul; }
  if (Decimal.neg)  { Decimal.negate   = Decimal.neg; Decimal.negated = Decimal.neg; }

  globalThis._decimalDivergenceHarnessInstalled = true;
  if (typeof _nativeLog === "function") {
    _nativeLog("[decimal-harness] installed, sampling 1 in " + everyN + " calls across " +
               protoNames.length + " prototype + " + staticNames.length + " static methods");
  }
};
