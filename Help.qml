import QtQuick
import QtQuick.Layouts
import qs.Commons
import "help.js" as HelpContent

// In-app help: a Shortcuts tab and a short Guide. Opened with F1, Ctrl+/ or the ? button.
// `host` is Pinly.qml's root item (theme colors and scaling helpers).
Rectangle {
  id: hp

  required property var host
  property string page: "keys"

  color: host.background
  radius: host.cornerRadius

  function handleKey(event) {
    var k = event.key
    if (k === Qt.Key_Escape || k === Qt.Key_F1) { host.helpOpen = false; return true }
    if (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Tab || k === Qt.Key_Backtab) {
      hp.page = hp.page === "keys" ? "guide" : "keys"
      return true
    }
    var step = k === Qt.Key_Up ? -60 : k === Qt.Key_Down ? 60 : k === Qt.Key_PageUp ? -flick.height * 0.9 : k === Qt.Key_PageDown ? flick.height * 0.9 : 0
    if (k === Qt.Key_Home) flick.contentY = 0
    else if (k === Qt.Key_End) flick.contentY = Math.max(0, flick.contentHeight - flick.height)
    else if (step !== 0) flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + step))
    return true
  }

  onPageChanged: flick.contentY = 0

  MouseArea { anchors.fill: parent }

  Item {
    id: head
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: host.sp(52)

    Text {
      id: headTitle
      anchors.left: parent.left
      anchors.leftMargin: host.sp(18)
      anchors.verticalCenter: parent.verticalCenter
      text: "Help"
      color: host.foreground
      font.family: host.fontFamily
      font.pixelSize: host.fs(Style.font.title)
      font.bold: true
    }

    Row {
      anchors.left: headTitle.right
      anchors.leftMargin: host.sp(16)
      anchors.verticalCenter: parent.verticalCenter
      spacing: host.sp(4)
      Repeater {
        model: [{ id: "keys", label: "Shortcuts" }, { id: "guide", label: "How to use it" }]
        delegate: Rectangle {
          required property var modelData
          height: host.sp(30)
          width: tabLabel.implicitWidth + host.sp(24)
          radius: height / 2
          color: hp.page === modelData.id ? host.accent : (tabMouse.containsMouse ? host.selectedBackground : host.surface)
          Text {
            id: tabLabel
            anchors.centerIn: parent
            text: modelData.label
            color: hp.page === modelData.id ? host.accentText : host.foreground
            font.family: host.fontFamily
            font.pixelSize: host.fs(Style.font.caption)
          }
          MouseArea {
            id: tabMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hp.page = modelData.id
          }
        }
      }
    }

    Text {
      anchors.right: closeBtn.left
      anchors.rightMargin: host.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      visible: !host.compactMode
      text: "←→ switch · ↑↓ scroll · Esc close"
      color: host.muted
      font.family: host.fontFamily
      font.pixelSize: host.fs(Style.font.caption)
    }

    Rectangle {
      id: closeBtn
      anchors.right: parent.right
      anchors.rightMargin: host.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      width: host.sp(30)
      height: width
      radius: host.innerRadius
      color: closeMouse.containsMouse ? host.selectedBackground : "transparent"
      Text {
        anchors.centerIn: parent
        text: host.glyph(0xF0156)
        color: host.muted
        font.family: host.fontFamily
        font.pixelSize: host.fs(Style.font.title)
      }
      MouseArea {
        id: closeMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: host.helpOpen = false
      }
    }

    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: Style.normalBorderWidth
      color: host.line
    }
  }

  Flickable {
    id: flick
    anchors.top: head.bottom
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: host.sp(18)
    contentWidth: width
    contentHeight: hp.page === "keys" ? keysFlow.implicitHeight : guideCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // Shortcuts: one card per section, two or three columns when there is room.
    Flow {
      id: keysFlow
      visible: hp.page === "keys"
      width: flick.width
      spacing: host.sp(14)
      readonly property int cols: Math.max(1, Math.min(3, Math.floor(width / host.sp(330))))
      readonly property real cardW: (width - spacing * (cols - 1)) / cols

      Repeater {
        model: HelpContent.shortcuts
        delegate: Rectangle {
          required property var modelData
          width: keysFlow.cardW
          height: cardCol.implicitHeight + host.sp(24)
          radius: host.innerRadius
          color: host.surface

          Column {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: host.sp(12)
            spacing: host.sp(6)

            Text {
              text: modelData.title
              color: host.accent
              font.family: host.fontFamily
              font.pixelSize: host.fs(Style.font.caption)
              font.bold: true
              bottomPadding: host.sp(2)
            }

            Repeater {
              model: modelData.items
              delegate: RowLayout {
                required property var modelData
                width: cardCol.width
                spacing: host.sp(10)
                Rectangle {
                  Layout.alignment: Qt.AlignTop
                  Layout.preferredWidth: Math.min(keyText.implicitWidth + host.sp(12), cardCol.width * 0.45)
                  Layout.preferredHeight: keyText.implicitHeight + host.sp(6)
                  radius: host.sp(4)
                  color: host.background
                  border.width: Style.normalBorderWidth
                  border.color: host.line
                  Text {
                    id: keyText
                    anchors.fill: parent
                    anchors.leftMargin: host.sp(6)
                    anchors.rightMargin: host.sp(6)
                    verticalAlignment: Text.AlignVCenter
                    text: modelData[0]
                    color: host.foreground
                    font.family: host.fontFamily
                    font.pixelSize: host.fs(Style.font.caption)
                    elide: Text.ElideRight
                  }
                }
                Text {
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  text: modelData[1]
                  color: host.muted
                  font.family: host.fontFamily
                  font.pixelSize: host.fs(Style.font.caption)
                  wrapMode: Text.WordWrap
                }
              }
            }
          }
        }
      }
    }

    // Guide: short sections in a readable column.
    Column {
      id: guideCol
      visible: hp.page === "guide"
      width: Math.min(flick.width, host.sp(720))
      x: (flick.width - width) / 2
      spacing: host.sp(18)

      Repeater {
        model: HelpContent.guide
        delegate: Column {
          required property var modelData
          width: guideCol.width
          spacing: host.sp(6)
          Text {
            text: modelData.title
            color: host.foreground
            font.family: host.fontFamily
            font.pixelSize: host.fs(Style.font.title)
            font.bold: true
          }
          Repeater {
            model: modelData.body
            delegate: Text {
              required property var modelData
              width: guideCol.width
              text: modelData
              textFormat: Text.PlainText
              color: host.muted
              font.family: host.fontFamily
              font.pixelSize: host.fs(Style.font.body)
              lineHeight: 1.25
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }
}
