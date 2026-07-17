// header-tick-helper.js — coalesce the late-tick header evals into one call.
//
// Before: pollDirect had 11+ tiny `evaluateScript` calls for late-header reads
// (tachyon gain, EP-threshold check, sidebar currency cycle for 8 currencies,
// EC-any-completion). Each one is a `vmEntryToJavaScriptTrampoline` and pays
// the parse cost of its source string every tick.
//
// After: one `_nativeHeaderLateTickReads()` call that returns JSON with all the
// fields, gated by the same flags Swift would have evaluated individually. The
// big celestial-combined block (2259-2539) is unchanged — it already coalesces
// the celestial reads. This helper is for everything south of that block.
//
// Late-game savings: ~10 trampolines/tick eliminated.
// Mid-game savings: 1-3 trampolines/tick depending on progression (only the
//                   sections behind reached flags fire anyway).
//
// No caching — every field is volatile per tick (currency values accumulate,
// gains recompute, EC completion status flips). This is pure coalescing.
//
// Lifecycle: injected from `GameEngine.setupHeaderTickHelper()`. Idempotent.
// Re-injected at every save-lifecycle entry point alongside the other helpers.

(function () {
    "use strict";

    // gateFlags is a tight numeric bitmask string ("01101101") to avoid the
    // overhead of passing an object. Bit positions:
    //   0: dilationActive  — `player.dilation.active` (drives tachyon gain text)
    //   1: dilationReached — drives TP / DT currency cycle
    //   2: effarigReached  — drives RelicShards
    //   3: imReached       — drives iM + MachinesCombined
    //   4: laitelaReached  — drives DarkMatter + DarkEnergy + Singularities
    //   5: anyECNeeded     — true when `eternityReached && ecUnlockedId == 0`
    //                        (forces the EC-completion fallback query)

    function bit(flags, i) { return flags.charAt(i) === "1"; }

    function safe(fn, fallback) {
        try { return fn(); } catch (e) { return fallback; }
    }

    globalThis._nativeHeaderLateTickReads = function (gateFlags) {
        gateFlags = String(gateFlags || "");
        var dilActive = bit(gateFlags, 0);
        var dilReached = bit(gateFlags, 1);
        var effReached = bit(gateFlags, 2);
        var imReached  = bit(gateFlags, 3);
        var laiReached = bit(gateFlags, 4);
        var anyECNeeded = bit(gateFlags, 5);

        var out = {
            // Always-on:
            epGteReality: safe(function () {
                return Currency.eternityPoints.value.gte("1e4000");
            }, false)
        };

        if (dilActive) {
            out.tachyonGain = safe(function () {
                return format(getTachyonGain(false), 2, 1);
            }, "0");
        }
        if (dilReached) {
            out.tpStr = safe(function () {
                return format(Currency.tachyonParticles.value, 2);
            }, "0");
            out.dtStr = safe(function () {
                return format(Currency.dilatedTime.value, 2);
            }, "0");
        }
        if (effReached) {
            out.relicShardsStr = safe(function () {
                return format(Currency.relicShards.value, 2);
            }, "0");
        }
        if (imReached) {
            out.imStr = safe(function () {
                return format(Currency.imaginaryMachines.value, 2);
            }, "0");
            out.machinesCombinedStr = safe(function () {
                return formatMachines(Currency.realityMachines.value,
                                      Currency.imaginaryMachines.value);
            }, "0");
        }
        if (laiReached) {
            out.darkMatterStr = safe(function () {
                return format(Currency.darkMatter.value, 2);
            }, "0");
            out.darkEnergyStr = safe(function () {
                return format(Currency.darkEnergy.value, 2, 2);
            }, "0");
            out.singularitiesStr = safe(function () {
                return format(Currency.singularities.value, 2);
            }, "0");
        }
        if (anyECNeeded) {
            out.anyECCompleted = safe(function () {
                return EternityChallenges.all.some(function (ec) {
                    return ec.completions > 0;
                });
            }, false);
        }

        return JSON.stringify(out);
    };
})();
