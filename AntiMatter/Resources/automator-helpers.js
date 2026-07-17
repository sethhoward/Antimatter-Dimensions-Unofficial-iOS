// automator-helpers.js
//
// Runtime-injected bridge for the Automator Constants editor (iOS port of
// AutomatorDefinePage.vue + AutomatorDefineSingleEntry.vue). Loaded by
// GameEngine.setupAutomatorHelpers() at every save-lifecycle entry point
// (finishStartup / importSave / hardReset / slot-switch / backup-restore),
// same pattern as celestial-helpers.js. Pure function definitions on
// globalThis — no webpack rebuild required.
//
// Constants live in player.reality.automator.constants (name -> value string)
// with player.reality.automator.constantSortOrder tracking insertion order.
// All mutations go through AutomatorBackend.{add,modify,rename,delete}Constant,
// which keep both fields in sync and dispatch GAME_EVENT.AUTOMATOR_CONSTANT_CHANGED.

(function () {
  "use strict";

  // Recalculate live-script errors after any constant change so scripts that
  // reference a just-defined constant resolve immediately (mirrors the Vue
  // handleFocus tail in AutomatorDefineSingleEntry.vue).
  function recalc() {
    try {
      if (typeof AutomatorData !== "undefined" && AutomatorData.recalculateErrors) {
        AutomatorData.recalculateErrors();
      }
    } catch (e) { /* no-op */ }
  }

  globalThis._nativeListAutomatorConstants = function () {
    try {
      const auto = player.reality.automator;
      const order = (auto.constantSortOrder && typeof auto.constantSortOrder[Symbol.iterator] === "function")
        ? Array.from(auto.constantSortOrder)
        : [];
      const consts = auto.constants || {};
      const list = order.map(name => ({ name: name, value: String(consts[name] == null ? "" : consts[name]) }));
      return JSON.stringify({
        constants: list,
        maxCount: AutomatorData.MAX_ALLOWED_CONSTANT_COUNT,
        maxNameLength: AutomatorData.MAX_ALLOWED_CONSTANT_NAME_LENGTH,
        maxValueLength: AutomatorData.MAX_ALLOWED_CONSTANT_VALUE_LENGTH,
      });
    } catch (e) {
      return JSON.stringify({ constants: [], maxCount: 30, maxNameLength: 20, maxValueLength: 250 });
    }
  };

  globalThis._nativeAddAutomatorConstant = function (name, value) {
    try { AutomatorBackend.addConstant(name, value); recalc(); } catch (e) { /* no-op */ }
  };

  globalThis._nativeModifyAutomatorConstant = function (name, value) {
    try { AutomatorBackend.modifyConstant(name, value); recalc(); } catch (e) { /* no-op */ }
  };

  globalThis._nativeRenameAutomatorConstant = function (oldName, newName) {
    try { AutomatorBackend.renameConstant(oldName, newName); recalc(); } catch (e) { /* no-op */ }
  };

  globalThis._nativeDeleteAutomatorConstant = function (name) {
    try { AutomatorBackend.deleteConstant(name); recalc(); } catch (e) { /* no-op */ }
  };

  // Mirror ClearConstantsModal.vue:20 — wipe both fields, then dispatch the
  // change event so any other listeners (and recalc) update.
  globalThis._nativeClearAutomatorConstants = function () {
    try {
      player.reality.automator.constants = {};
      player.reality.automator.constantSortOrder = [];
      if (typeof EventHub !== "undefined" && typeof GAME_EVENT !== "undefined") {
        EventHub.dispatch(GAME_EVENT.AUTOMATOR_CONSTANT_CHANGED);
      }
      recalc();
    } catch (e) { /* no-op */ }
  };

  // Mirror ImportTimeStudyConstants.vue importConstants() — import each saved
  // Time Study preset (with non-empty studies) as a constant. Name format and
  // the addConstant count guard match web exactly.
  globalThis._nativeImportTSConstantsAsConstants = function () {
    try {
      const presets = (player.timestudy.presets || []).filter(p => p && p.studies !== "");
      for (let index = 0; index < presets.length; index++) {
        const rawName = String(presets[index].name == null ? "" : presets[index].name);
        const name = `TSPreset${index + 1}__${rawName.replaceAll(/[^a-zA-Z_0-9]/gu, "_")}`;
        AutomatorBackend.modifyConstant(name, presets[index].studies);
      }
      recalc();
    } catch (e) { /* no-op */ }
  };

  // Replicates AutomatorDefineSingleEntry.currentError() (lines 35-63). Returns
  // an error string, or "" if the constant is valid. `oldName` is the constant's
  // previous name (empty when adding) so a rename to itself isn't flagged as a
  // duplicate. Degrades gracefully if forbiddenConstantPatterns / TimeStudyTree
  // aren't on globalThis (skips that sub-check rather than throwing).
  globalThis._nativeValidateAutomatorConstant = function (name, value, oldName) {
    try {
      if (!name) return "";

      const isValidName = name.match(/^[a-zA-Z_][a-zA-Z_0-9]*$/u);
      const consts = player.reality.automator.constants || {};
      const alreadyExists = Object.keys(consts).includes(name) && name !== oldName;

      let hasCommandConflict = false;
      if (typeof forbiddenConstantPatterns !== "undefined" && forbiddenConstantPatterns) {
        const lower = name.toLowerCase();
        hasCommandConflict = forbiddenConstantPatterns.some(p => {
          const matchObj = lower.match(p);
          return matchObj ? matchObj[0] === lower : false;
        });
      }

      const shadowsPrototype = ["constructor", "hasOwnProperty", "isPrototypeOf", "propertyIsEnumerable",
        "toLocaleString", "toString", "toValueOf"].some(p => name.match(p));

      if (!isValidName) return "Constant name must be alphanumeric without spaces and cannot start with a number";
      if (alreadyExists) return "You have already defined a constant with this name";
      if (hasCommandConflict) return "Constant name conflicts with a command key word";
      if (shadowsPrototype) return "Constant name cannot shadow a built-in Javascript prototype prop";

      if (!value) return "Constant value cannot be empty";

      const isNumber = value.match(/^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$/u);
      let isStudyString = false;
      if (typeof TimeStudyTree !== "undefined" && TimeStudyTree.isValidImportString) {
        isStudyString = TimeStudyTree.isValidImportString(value);
      }

      if (!isNumber && !isStudyString) return "Constant value must either be a number or Time Study string";
      return "";
    } catch (e) {
      return "";
    }
  };
})();
