// JIT microbenchmark workload — runs in BOTH JSContext and WKWebView.
// Goal: measure raw Decimal arithmetic throughput so we can compare
// the no-JIT path (JSContext) against the JIT path (WKWebView's
// out-of-process WebContent service). The loop is intentionally tight
// and arithmetically dense to surface JIT's effect: a hot mantissa/
// exponent pipeline is exactly the workload offline simulation is
// dominated by (per-tick AD/ID/TD multiplier chains via timesEffectsOf).

(function() {
    if (typeof Decimal === 'undefined') {
        globalThis._runJITBench = function() {
            return { elapsedMs: -1, checksum: 'ERROR: Decimal not defined' };
        };
        return;
    }

    globalThis._runJITBench = function(iterations) {
        var t0 = Date.now();
        var acc = new Decimal("1.5e10");
        var multiplier = new Decimal("1.0001e3");
        var increment = new Decimal("3.7e8");
        var cap = new Decimal("1e300");
        var reset = new Decimal("1e10");
        for (var i = 0; i < iterations; i++) {
            acc = acc.times(multiplier);
            acc = acc.plus(increment);
            if (acc.gt(cap)) acc = reset;
        }
        // Checksum is returned as a string so JIT can't elide the loop —
        // the final value is observed externally. Both contexts must
        // produce byte-identical output for the speedup number to mean
        // anything.
        return { elapsedMs: Date.now() - t0, checksum: acc.toString() };
    };
})();
