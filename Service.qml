// Omaglass — service half. Keeps glass.lua loaded in the running Hyprland.
//
// Same mechanism as Omachill: a `hyprctl reload` rebuilds Hyprland's Lua
// state from the config files and nothing else, so the config loads the
// engine itself —
//
//   ~/.config/hypr/omaglass.lua       written here on every start and on
//                                     every settings change: the options,
//                                     then dofile(glass.lua). Removed when
//                                     this service goes away.
//   ~/.config/hypr/hyprland.lua       one guarded line appended once (marked
//                                     block), dofile()ing the loader if it
//                                     exists. The only edit to a user file.
//
//   shell start / plugin (re)load   -> write loader, ensure the include,
//                                      `hyprctl eval dofile(loader)` for
//                                      immediate effect (retry while
//                                      Hyprland is not ready)
//   any `hyprctl reload`            -> the config re-runs the loader
//   widget settings change          -> rewrite the loader, inject again
//   plugin disabled / shell exit    -> omaglass.unload() (only our own
//                                      engine), loader removed
//
// After an inject it probes for the hyprglass plugin once and raises a
// notification if it is missing: the rules still apply, the material does
// not.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Item {
  id: root
  visible: false

  // Injected by the shell after construction (see shell.qml ensureService).
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "io.github.nocstah.omaglass"

  // Our own directory, resolved from this file's URL. Deliberately NOT from
  // manifest.__sourceDir: the shell assigns `manifest` after construction and
  // bindings on it have not re-evaluated when onManifestChanged fires, so a
  // path derived from it is still "" at the moment the first inject runs.
  readonly property string sourceDir: {
    const url = Qt.resolvedUrl(".").toString()
    return url.replace(/^file:\/\//, "").replace(/\/$/, "")
  }
  readonly property string enginePath: sourceDir + "/glass.lua"
  readonly property string loaderPath: Quickshell.env("HOME") + "/.config/hypr/omaglass.lua"
  readonly property string hyprlandLua: Quickshell.env("HOME") + "/.config/hypr/hyprland.lua"

  property string lastOpts: ""
  property int attempts: 0
  property bool injected: false

  // One stamp per Service instance, handed to the engine and checked by the
  // unload below. When the shell hot-reloads this plugin (any write under
  // its directory), the old instance's detached `omaglass.unload()` races
  // the new instance's inject — and when it loses, it tears down the fresh
  // engine: no key, no bar toggle, and the next `hyprctl reload` hands
  // SUPER + SHIFT + C back to the Calendar webapp. Seen 2026-09-02. With the
  // stamp, a stale unload finds a newer engine and leaves it alone.
  readonly property string generation: String(Date.now()) + "-" + String(Math.floor(Math.random() * 1e9))

  // ---- settings -----------------------------------------------------------
  // A service gets no `settings`; read the widget's entry out of shell.json
  // (bar.layout.<section>[] first, then plugins[]) the way quickshell.spotify
  // does. Keys missing there fall back to the manifest defaults.
  function entryFor(config) {
    if (!config) return null
    const sections = ["left", "center", "right"]
    const layout = config.bar && config.bar.layout ? config.bar.layout : {}
    for (let s = 0; s < sections.length; s++) {
      const list = layout[sections[s]]
      if (!Array.isArray(list)) continue
      for (let i = 0; i < list.length; i++) {
        const e = list[i]
        if (e && (e.id === pluginId || e === pluginId)) return typeof e === "object" ? e : {}
      }
    }
    const plugins = Array.isArray(config.plugins) ? config.plugins : []
    for (let i = 0; i < plugins.length; i++) {
      const e = plugins[i]
      if (e && (e.id === pluginId || e === pluginId)) return typeof e === "object" ? e : {}
    }
    return null
  }

  function readSettings() {
    const d = manifest && manifest.barWidget && manifest.barWidget.defaults ? manifest.barWidget.defaults : {}
    const e = entryFor(shell ? shell.shellConfig : null) || {}
    function pick(k, fb) { return e[k] !== undefined && e[k] !== null ? e[k] : (d[k] !== undefined ? d[k] : fb) }
    return {
      terminals: Boolean(pick("terminals", true)),
      background: Boolean(pick("background", true)),
      chilled: Boolean(pick("chilled", true)),
      layers: Boolean(pick("layers", true)),
      frost: Number(pick("frost", 30)),
      shadow: Boolean(pick("shadow", true)),
      shadowRange: Number(pick("shadowRange", 28)),
      shadowStrength: Number(pick("shadowStrength", 28)),
      shadowClip: Boolean(pick("shadowClip", true)),
      inactiveShadowOff: Boolean(pick("inactiveShadowOff", true)),
      alphaLight: Number(pick("alphaLight", 72)),
      alphaDark: Number(pick("alphaDark", 62)),
      milkyAlpha: Number(pick("milkyAlpha", 65)),
      clearAlpha: Number(pick("clearAlpha", 45)),
      keyReadability: String(pick("keyReadability", "SUPER + CTRL + G")),
      keyLooks: String(pick("keyLooks", "SUPER + CTRL + ALT + G")),
      notify: Boolean(pick("notify", true)),
    }
  }

  function luaString(s) {
    return "\"" + String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, " ") + "\""
  }

  function luaOpts(s) {
    const b = function(v) { return v ? "true" : "false" }
    return "GLASS_OPTS = { terminals = " + b(s.terminals) + ", background = " + b(s.background)
      + ", chilled = " + b(s.chilled) + ", layers = " + b(s.layers) + ", frost = " + s.frost
      + ", shadow = " + b(s.shadow) + ", shadow_range = " + s.shadowRange + ", shadow_strength = " + s.shadowStrength
      + ", shadow_clip = " + b(s.shadowClip) + ", inactive_shadow_off = " + b(s.inactiveShadowOff)
      + ", alpha_light = " + s.alphaLight + ", alpha_dark = " + s.alphaDark
      + ", milky_alpha = " + s.milkyAlpha + ", clear_alpha = " + s.clearAlpha
      + ", key_readability = " + luaString(s.keyReadability) + ", key_looks = " + luaString(s.keyLooks)
      + ", notify = " + b(s.notify) + ", helper = " + luaString(sourceDir + "/bin/glass-foot")
      + ", generation = " + luaString(generation) + " }"
  }

  // ---- injection ----------------------------------------------------------
  function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  // The loader Hyprland's config runs on every reload.
  function loaderText(opts) {
    return "-- Omaglass (io.github.nocstah.omaglass) — written by the shell plugin on\n"
      + "-- every start and settings change, removed when it is disabled. Loaded\n"
      + "-- from hyprland.lua so the glass engine is re-created on every\n"
      + "-- `hyprctl reload`, which rebuilds Hyprland's Lua state from scratch.\n"
      + "-- Do not edit: settings live in the bar widget (shell.json).\n"
      + opts + "\n"
      + "local engine = " + luaString(enginePath) + "\n"
      + "local f = io.open(engine, \"r\")\n"
      + "if f then f:close() dofile(engine) end\n"
  }

  // One guarded include, appended once to the user's hyprland.lua.
  readonly property string includeMarker: ">>> io.github.nocstah.omaglass"
  readonly property string includeBlock:
    "\n-- " + includeMarker + ": glass engine, re-created on every reload (line managed by the plugin) >>>\n"
    + "do local p = os.getenv(\"HOME\") .. \"/.config/hypr/omaglass.lua\"; local f = io.open(p, \"r\"); if f then f:close(); dofile(p) end end\n"
    + "-- <<< io.github.nocstah.omaglass <<<\n"

  function inject() {
    if (!enginePath) return
    if (injectProc.running) { pending = true; return }
    const opts = luaOpts(readSettings())
    lastOpts = opts
    const script =
      "set -e; printf '%s' " + shellQuote(loaderText(opts)) + " > " + shellQuote(loaderPath) + "; "
      + "if [ -f " + shellQuote(hyprlandLua) + " ] && ! grep -qF " + shellQuote(includeMarker) + " " + shellQuote(hyprlandLua) + "; then "
      + "printf '%s' " + shellQuote(includeBlock) + " >> " + shellQuote(hyprlandLua) + "; fi; "
      + "exec hyprctl eval " + shellQuote("dofile(" + luaString(loaderPath) + ")")
    injectProc.command = ["bash", "-c", script]
    injectProc.running = true
  }

  property bool pending: false

  Process {
    id: injectProc
    running: false
    stdout: StdioCollector { id: injectOut; waitForEnd: true }
    onExited: function(code) {
      const out = String(injectOut.text || "").trim()
      if (code === 0 && out.indexOf("ok") === 0) {
        root.injected = true
        root.attempts = 0
        if (!root.probed) { root.probed = true; probeProc.running = true }
      } else {
        root.injected = false
        root.attempts += 1
        console.warn("[omaglass] inject failed (" + code + "): " + out)
        if (root.attempts < 20) retry.restart()
      }
      if (root.pending) { root.pending = false; root.inject() }
    }
  }

  // Once per service: is the hyprglass plugin there? Without it the rules
  // still apply but there is no material — say so, once.
  property bool probed: false
  Process {
    id: probeProc
    running: false
    command: ["hyprctl", "eval", "assert(hl.plugin and hl.plugin.hyprglass, 'no hyprglass')"]
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: function(code) {
      if (code === 0 && String(probeOut.text || "").indexOf("ok") === 0) return
      Quickshell.execDetached(["omarchy-notification-send", "-u", "normal", "Omaglass: hyprglass plugin not loaded",
        "Terminals will not be glass until it is. See the plugin README for the two-line install."])
    }
  }

  // Hyprland can still be parsing its config when the shell comes up.
  Timer {
    id: retry
    interval: 1500
    repeat: false
    onTriggered: root.inject()
  }

  // manifest (and with it sourceDir) is assigned AFTER Component.onCompleted,
  // so the first injection is driven from here, not from onCompleted.
  // First injection once the shell has handed us `shell` (settings live in
  // shell.shellConfig). manifest arrives last, so it is the trigger.
  onManifestChanged: inject()

  // Settings edited in the widget (omarchy bar set) rewrite shell.json;
  // re-inject only when the resulting options actually differ.
  Connections {
    target: root.shell
    ignoreUnknownSignals: true
    function onShellConfigChanged() {
      if (!root.enginePath) return
      if (root.luaOpts(root.readSettings()) !== root.lastOpts) root.inject()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      if (String(event.name) === "configreloaded") root.inject()
    }
  }

  // `omarchy-shell omaglass status` / `omarchy-shell omaglass inject`
  IpcHandler {
    target: "omaglass"
    function status(): string {
      return JSON.stringify({ injected: root.injected, attempts: root.attempts, engine: root.enginePath, opts: root.lastOpts })
    }
    function inject(): string { root.inject(); return "ok" }
  }

  Component.onDestruction: {
    // Disable / remove / shell restart: leave the compositor as we found it
    // (minus the Calendar key the engine displaced — a `hyprctl reload`
    // brings that back). Only OUR engine, though: on a plugin hot-reload the
    // replacement instance may already have injected a newer one.
    // The loader goes too: a reload after this must not resurrect an engine
    // for a plugin that was disabled or removed.
    Quickshell.execDetached(["bash", "-c",
      "rm -f " + shellQuote(loaderPath) + "; exec hyprctl eval " + shellQuote(
        "if type(omaglass) == 'table' and omaglass.unload and omaglass.generation == "
        + luaString(generation) + " then omaglass.unload() end")])
  }
}
