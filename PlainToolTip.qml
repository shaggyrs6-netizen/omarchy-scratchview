import QtQuick
import QtQuick.Controls

// Never let application-controlled titles be interpreted as HTML/AutoText.
// Shared by the panel and bar: safety must not depend on the host bar's tooltip.
ToolTip {
    id: tip
    property color foreground: '#f3f0e9'
    property color backgroundColor: '#171723'
    property color outline: '#a8a8b8'
    width: Math.min(420, implicitWidth)
    delay: 500
    contentItem: Text {
        text: tip.text
        textFormat: Text.PlainText
        font: tip.font
        color: tip.foreground
        wrapMode: Text.Wrap
    }
    background: Rectangle {
        color: tip.backgroundColor
        border.color: tip.outline
        radius: 5
    }
}
