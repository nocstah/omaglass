// Omaglass — bar widget. Shows the focused window's glass look and opens the
// dropdown (Panel.qml) on click; middle-click cycles the looks directly.
// Lights up (theme blue) while the focused window is in a non-default look.
//
// State comes from the engine: `custom>>omaglass <address> <look>` events on
// the Hyprland socket trigger a refresh, and the refresh reads the focused
// window's tags from `hyprctl activewindow -j` (the glass_<look> tag is the
// engine's only state, so this can never disagree with it).
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "io.github.nocstah.omaglass"

  readonly property bool hideWhenIdle: setting("hideWhenIdle", false) === true

  // The theme's blue, read from the active theme's colors.toml (fallbacks:
  // `blue`, ANSI `color4`, the accent, a fixed blue). Same as Omachill.
  property color themeBlue: "#3b82f6"
  function parseThemeBlue(raw) {
    const lines = String(raw || "").split("\n")
    let blue = "", c4 = ""
    for (let i = 0; i < lines.length; i++) {
      const m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!m) continue
      if (m[1] === "blue") blue = m[2]
      else if (m[1] === "color4") c4 = m[2]
    }
    themeBlue = blue || c4 || (Color.accent ? String(Color.accent) : "#3b82f6")
  }
  FileView {
    id: themeColorsFile
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: false
    printErrors: false
    onLoaded: root.parseThemeBlue(text())
    onLoadFailed: root.parseThemeBlue("")
  }
  Connections {
    target: Color
    function onAccentChanged() { themeColorsFile.reload() }
    function onForegroundChanged() { themeColorsFile.reload() }
  }

  // Focused window: its look ("glass" = default, "" = not a glass window).
  property string look: ""
  property string title: ""
  property string defaultLook: "glass"
  readonly property bool glassWindow: look !== ""
  readonly property bool active: glassWindow && look !== "glass"
  readonly property bool shown: active || !hideWhenIdle

  implicitWidth: shown ? button.implicitWidth : 0
  implicitHeight: shown ? button.implicitHeight : 0
  visible: shown

  function refresh() {
    if (activeProc.running) return
    activeProc.running = true
  }

  function cycle(readability) {
    root.bar.run("hyprctl eval " + Util.shellQuote(readability ? "omaglass.cycle_readability()" : "omaglass.cycle_looks()"))
  }

  // The dropdown, a shell Panel loaded beside the widget (weather's pattern).
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  Process {
    id: activeProc
    running: false
    command: ["hyprctl", "-j", "activewindow"]
    stdout: StdioCollector {
      id: activeOut
      waitForEnd: true
      onStreamFinished: {
        let look = "", title = ""
        try {
          const w = JSON.parse(String(activeOut.text || "{}"))
          const tags = Array.isArray(w.tags) ? w.tags : []
          let enabled = false, disabled = false, found = ""
          for (let t = 0; t < tags.length; t++) {
            const n = String(tags[t]).replace(/\*$/, "")
            if (n === "hyprglass_enabled") enabled = true
            else if (n === "hyprglass_disabled") disabled = true
            const m = n.match(/^glass_([a-z]+)$/)
            if (m) found = m[1]
          }
          if (found) look = found
          else if (enabled && !disabled) look = "glass"
          title = String(w.title || w.class || "")
        } catch (e) {
          console.warn("[omaglass] activewindow parse failed: " + e)
        }
        root.look = look
        root.title = title
        defaultFile.reload()
      }
    }
  }

  // The default for new windows, kept by the engine.
  FileView {
    id: defaultFile
    path: Quickshell.env("HOME") + "/.local/state/omaglass/default-look"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.defaultLook = String(text() || "glass").trim() || "glass"
    onLoadFailed: root.defaultLook = "glass"
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      const n = String(event.name)
      if (n === "custom") {
        if (String(event.data || "").indexOf("omaglass") === 0) root.refresh()
      } else if (n === "activewindowv2" || n === "configreloaded" || n === "closewindow" || n === "focusedmonv2") {
        root.refresh()
      }
    }
  }

  Component.onCompleted: refresh()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰂵"  // nf-md-blur
    active: root.active
    activeColor: root.themeBlue
    tooltipText: root.glassWindow
      ? "Glass: " + root.look + " — " + root.title + "\nclick: choose a look · middle-click: next look"
      : (root.title ? root.title + " is not a glass window" : "No focused window")
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.cycle(false)
      else root.togglePanel()
    }
  }
}
