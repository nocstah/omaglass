// Omaglass — the dropdown. Opened from the bar widget. Two pages:
//   looks     — a scope switch (focused window / all windows), the looks in
//               two sections with a one-line description each, the shadows
//               mode. "All windows" applies the look to every glass window
//               and makes it the default for windows opened from now on.
//   settings  — every widget setting in manifest.json's schema, grouped in
//               tabs and drawn by type (toggle, slider, button group). A
//               change is written with `omarchy bar set`; the service turns
//               that into a Hyprland reload on the spot, no restart.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.nocstah.omaglass"
  ipcTarget: "io.github.nocstah.omaglass"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // "all" | "window" — All first: the look is usually a desktop-wide choice.
  property string scope: "all"
  readonly property string currentLook: hostWidget ? String(hostWidget.look || "") : ""
  readonly property string currentTitle: hostWidget ? String(hostWidget.title || "") : ""
  readonly property string defaultLook: hostWidget ? String(hostWidget.defaultLook || "glass") : "glass"

  readonly property var readability: [
    { name: "glass", label: "Glass", text: "The theme's frost with the wallpaper behind it. The default." },
    { name: "milky", label: "Milky", text: "The frost, but the terminal's own background lighter — text on a calmer ground." },
    { name: "solid", label: "Solid", text: "Opaque in the theme colour. Maximum readability, no glass." },
  ]
  readonly property var looks: [
    { name: "clear", label: "Clear", text: "The wallpaper sharp through the pane, no frost. Windows beneath never show." },
    { name: "pure", label: "Pure", text: "Super clear: the wallpaper exactly as it is behind the text. No frost, no tint, no terminal background." },
    { name: "sheer", label: "Sheer", text: "The lightest frost; the wallpaper stays recognisable." },
    { name: "native", label: "Native", text: "Hyprland's own blur instead of the glass — this one shows what is beneath." },
    { name: "contrast", label: "Contrast", text: "hyprglass's high-contrast preset: stronger tint, refraction." },
    { name: "block", label: "Block", text: "hyprglass's glass-block preset: lensing and chromatic aberration." },
  ]

  // ---- settings: the manifest's schema and defaults; `settings` (from the
  // bar widget, re-injected whenever shell.json changes) holds the overrides.
  property var manifest: ({})
  FileView {
    id: manifestFile
    path: String(Qt.resolvedUrl("manifest.json")).replace(/^file:\/\//, "")
    watchChanges: false
    printErrors: false
    onLoaded: { try { root.manifest = JSON.parse(text()) } catch (e) { root.manifest = {} } }
  }
  readonly property var schema: (manifest && manifest.barWidget && manifest.barWidget.schema) ? manifest.barWidget.schema : []
  readonly property var defaults: (manifest && manifest.barWidget && manifest.barWidget.defaults) ? manifest.barWidget.defaults : ({})
  function value(key) {
    const s = root.settings || {}
    if (s[key] !== undefined && s[key] !== null) return s[key]
    return root.defaults ? root.defaults[key] : undefined
  }
  readonly property string shadowsMode: String(root.value("shadows") || "contact")
  function setOption(key, v) {
    if (!root.bar) return
    root.bar.run("omarchy bar set io.github.nocstah.omaglass " + key + " " + Util.shellQuote(String(v)))
  }
  readonly property color panelForeground: root.bar ? root.bar.foreground : Color.popups.text

  // ---- pages and tabs
  property string page: "looks"
  property string tab: "Glass"
  readonly property var tabs: ["Glass", "Shadows", "Alpha", "Widget"]
  readonly property var tabOf: ({
    terminals: "Glass", background: "Glass", chilled: "Glass", layers: "Glass", nativeBlur: "Glass", frost: "Glass",
    shadows: "Shadows", shadowRange: "Shadows", shadowStrength: "Shadows", shadowClip: "Shadows",
    alphaLight: "Alpha", alphaDark: "Alpha", milkyAlpha: "Alpha", clearAlpha: "Alpha",
  })
  function entriesFor(t) {
    const out = []
    for (let i = 0; i < root.schema.length; i++) {
      const e = root.schema[i]
      if (!e || !e.key) continue
      if ((root.tabOf[e.key] || "Widget") === t) out.push(e)
    }
    return out
  }

  function apply(name) {
    if (!root.bar) return
    const call = root.scope === "all" ? "omaglass.set_all(" + JSON.stringify(name) + ")" : "omaglass.set(" + JSON.stringify(name) + ")"
    root.bar.run("hyprctl eval " + Util.shellQuote(call))
    if (root.scope !== "all") root.close()
  }

  function open() { root.controller.show(); if (hostWidget && hostWidget.refresh) hostWidget.refresh() }
  function openFromHotkey() { open() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        // ---- header: title + scope (looks) / back button (settings)
        Item {
          width: parent.width
          height: Math.max(titleCol.height, root.page === "looks" ? scopeGroup.height : backButton.height)
          Column {
            id: titleCol
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              text: root.page === "looks" ? "Glass" : "Glass settings"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              text: root.page === "looks"
                ? (root.scope === "all"
                    ? "Every glass window, and new ones from now on"
                    : (root.currentLook ? root.currentTitle.substring(0, 34) : "Focused window is not a glass window"))
                : "Applied on the spot; each change reloads Hyprland's config"
              color: Color.popups.text
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: Math.max(80, column.width - (root.page === "looks" ? scopeGroup.width : backButton.width) - Style.space(12))
            }
          }
          ButtonGroup {
            id: scopeGroup
            visible: root.page === "looks"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            options: ["Window", "All"]
            value: root.scope === "all" ? "All" : "Window"
            focusable: false
            onChanged: function(v) { root.scope = v === "All" ? "all" : "window" }
          }
          PanelActionButton {
            id: backButton
            visible: root.page === "settings"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰅁"
            tooltipText: "Back to looks"
            foreground: root.panelForeground
            onClicked: root.page = "looks"
          }
        }

        // ---- settings: the tab strip
        ButtonGroup {
          visible: root.page === "settings"
          options: root.tabs
          value: root.tab
          focusable: false
          onChanged: function(v) { root.tab = v }
        }

        PanelSeparator { width: parent.width }

        // =====================================================================
        // Looks page
        // =====================================================================
        Column {
          visible: root.page === "looks"
          width: parent.width
          spacing: Style.space(10)

          Repeater {
            model: [
              { title: "Readability", items: root.readability },
              { title: "Looks", items: root.looks },
            ]
            delegate: Column {
              required property var modelData
              width: column.width
              spacing: Style.space(2)
              PanelSectionHeader { text: modelData.title }
              Repeater {
                model: modelData.items
                delegate: Rectangle {
                  id: row
                  required property var modelData
                  readonly property bool current: root.scope === "all"
                    ? root.defaultLook === modelData.name
                    : root.currentLook === modelData.name
                  width: column.width
                  height: rowCol.implicitHeight + Style.space(12)
                  radius: Style.space(6)
                  color: current ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                       : (rowMouse.containsMouse ? Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.06) : "transparent")
                  Column {
                    id: rowCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    spacing: Style.space(2)
                    Text {
                      text: modelData.label + (row.current ? "  ·  current" : "")
                      color: row.current ? Color.accent : Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: row.current
                    }
                    Text {
                      text: modelData.text
                      color: Color.popups.text
                      opacity: 0.65
                      width: parent.width
                      wrapMode: Text.WordWrap
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }
                  MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.apply(modelData.name)
                  }
                }
              }
            }
          }

          PanelSeparator { width: parent.width }

          // ---- the setting worth reaching for from here, plus the way in
          Item {
            width: parent.width
            height: Math.max(shadowsLabel.height, shadowsGroup.height)
            Column {
              id: shadowsLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                text: "Shadows"
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              Text {
                text: root.shadowsMode === "flat" ? "None at all"
                    : root.shadowsMode === "theme" ? "The theme's own, no contact shadow"
                    : "Theme's on the focused window, contact shadow where a pane covers another"
                color: Color.popups.text
                opacity: 0.6
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                width: Math.max(80, column.width - shadowsGroup.width - Style.space(12))
                wrapMode: Text.WordWrap
              }
            }
            ButtonGroup {
              id: shadowsGroup
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              options: ["Contact", "Theme", "Flat"]
              value: root.shadowsMode === "flat" ? "Flat" : root.shadowsMode === "theme" ? "Theme" : "Contact"
              focusable: false
              onChanged: function(v) { root.setOption("shadows", v.toLowerCase()) }
            }
          }
          Item {
            width: parent.width
            height: settingsButton.height
            PanelActionButton {
              id: settingsButton
              anchors.right: parent.right
              iconText: "󰒓"
              tooltipText: "Settings"
              foreground: root.panelForeground
              onClicked: root.page = "settings"
            }
          }
        }

        // =====================================================================
        // Settings page: one row per schema entry of the current tab
        // =====================================================================
        Column {
          visible: root.page === "settings"
          width: parent.width
          spacing: Style.space(10)

          Repeater {
            model: root.entriesFor(root.tab)
            delegate: Column {
              id: srow
              required property var modelData
              readonly property var e: modelData
              readonly property var v: root.value(modelData.key)
              // What the control shows between the write and the shell
              // handing the new value back (a second or so): the value just
              // chosen, so a slider does not snap back meanwhile.
              property var pending: undefined
              onVChanged: pending = undefined
              readonly property var shown: pending !== undefined ? pending : v
              width: column.width
              spacing: Style.space(2)

              // ---- boolean: label + description, switch on the right
              Item {
                visible: srow.e.type === "boolean"
                width: parent.width
                height: visible ? Math.max(bCol.implicitHeight, bSwitch.implicitHeight) + Style.space(4) : 0
                Column {
                  id: bCol
                  anchors.left: parent.left
                  anchors.right: bSwitch.left
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)
                  Text {
                    text: srow.e.label || srow.e.key
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: srow.e.description || ""
                    visible: text !== ""
                    color: Color.popups.text
                    opacity: 0.6
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
                ToggleSwitch {
                  id: bSwitch
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  checked: srow.shown === true
                  foreground: root.panelForeground
                  accent: Color.accent
                  onToggled: { const next = !(srow.shown === true); srow.pending = next; root.setOption(srow.e.key, next) }
                }
              }

              // ---- integer: label and value above a slider
              Column {
                visible: srow.e.type === "integer"
                width: parent.width
                spacing: Style.space(2)
                Item {
                  width: parent.width
                  height: iLabel.height
                  Text {
                    id: iLabel
                    anchors.left: parent.left
                    text: srow.e.label || srow.e.key
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    anchors.right: parent.right
                    text: String(Math.round(iSlider.dragging ? iSlider.liveValue : Number(srow.shown)))
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }
                PanelSlider {
                  id: iSlider
                  bar: root.bar
                  width: parent.width
                  minimum: Number(srow.e.min !== undefined ? srow.e.min : 0)
                  maximum: Number(srow.e.max !== undefined ? srow.e.max : 100)
                  step: Number(srow.e.step !== undefined ? srow.e.step : 1)
                  integer: true
                  value: Number(srow.shown)
                  onReleased: function(x) { const n = Math.round(x); srow.pending = n; root.setOption(srow.e.key, n) }
                }
                Text {
                  text: srow.e.description || ""
                  visible: text !== ""
                  color: Color.popups.text
                  opacity: 0.6
                  width: parent.width
                  wrapMode: Text.WordWrap
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- enum: label with the button group on the right, the
              // description underneath at full width
              Column {
                visible: srow.e.type === "enum"
                width: parent.width
                spacing: Style.space(2)
                Item {
                  width: parent.width
                  height: Math.max(eLabel.height, eGroup.height)
                  Text {
                    id: eLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: srow.e.label || srow.e.key
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                  ButtonGroup {
                    id: eGroup
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    focusable: false
                    options: (srow.e.options || []).map(function(o) { return o.label || String(o.value) })
                    value: {
                      const os = srow.e.options || []
                      for (let i = 0; i < os.length; i++)
                        if (String(os[i].value) === String(srow.shown)) return os[i].label || String(os[i].value)
                      return ""
                    }
                    onChanged: function(l) {
                      const os = srow.e.options || []
                      for (let i = 0; i < os.length; i++) {
                        if ((os[i].label || String(os[i].value)) === l) { srow.pending = os[i].value; root.setOption(srow.e.key, os[i].value); return }
                      }
                    }
                  }
                }
                Text {
                  text: srow.e.description || ""
                  visible: text !== ""
                  color: Color.popups.text
                  opacity: 0.6
                  width: parent.width
                  wrapMode: Text.WordWrap
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- string (the key bindings): shown, changed from the CLI
              Column {
                visible: srow.e.type === "string"
                width: parent.width
                spacing: Style.space(2)
                Item {
                  width: parent.width
                  height: sLabel.height
                  Text {
                    id: sLabel
                    anchors.left: parent.left
                    text: srow.e.label || srow.e.key
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    anchors.right: parent.right
                    text: String(srow.shown === undefined ? "" : srow.shown)
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }
                Text {
                  text: (srow.e.description ? srow.e.description + " " : "") + "Change it with: omarchy bar set io.github.nocstah.omaglass " + srow.e.key + " \"SUPER + …\""
                  color: Color.popups.text
                  opacity: 0.6
                  width: parent.width
                  wrapMode: Text.WordWrap
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
    }
  }
}
