// Omaglass — the dropdown. Opened from the bar widget: a scope switch
// (focused window / all windows) and the looks in two sections, each with a
// one-line description; the focused window's current look is marked.
// "All windows" applies the look to every glass window and makes it the
// default for windows opened from now on.
import QtQuick
import Quickshell
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

  // "window" | "all"
  property string scope: "window"
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
    { name: "sheer", label: "Sheer", text: "The lightest frost; the wallpaper stays recognisable." },
    { name: "native", label: "Native", text: "Hyprland's own blur instead of the glass — this one shows what is beneath." },
    { name: "contrast", label: "Contrast", text: "hyprglass's high-contrast preset: stronger tint, refraction." },
    { name: "block", label: "Block", text: "hyprglass's glass-block preset: lensing and chromatic aberration." },
  ]

  // Widget settings have no editor in the shell (the schema is CLI-only:
  // `omarchy bar set io.github.nocstah.omaglass <key> <value>`), so the ones
  // worth reaching for live here.
  readonly property string shadowsMode: settings && settings.shadows ? String(settings.shadows) : "contact"
  function setOption(key, value) {
    if (!root.bar) return
    root.bar.run("omarchy bar set io.github.nocstah.omaglass " + key + " " + Util.shellQuote(String(value)))
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

        // ---- header: title + scope
        Item {
          width: parent.width
          height: Math.max(titleCol.height, scopeGroup.height)
          Column {
            id: titleCol
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              text: "Glass"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              text: root.scope === "all"
                ? "Every glass window, and new ones from now on"
                : (root.currentLook ? root.currentTitle.substring(0, 34) : "Focused window is not a glass window")
              color: Color.popups.text
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: Math.max(80, column.width - scopeGroup.width - Style.space(12))
            }
          }
          ButtonGroup {
            id: scopeGroup
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            options: ["Window", "All"]
            value: root.scope === "all" ? "All" : "Window"
            focusable: false
            onChanged: function(v) { root.scope = v === "All" ? "all" : "window" }
          }
        }

        PanelSeparator { width: parent.width }

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

        // ---- settings worth reaching for
        Column {
          width: parent.width
          spacing: Style.space(6)
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
          Text {
            text: "More settings: omarchy bar set io.github.nocstah.omaglass <key> <value> — frost, alphas, keys, which windows"
            color: Color.popups.text
            opacity: 0.45
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
