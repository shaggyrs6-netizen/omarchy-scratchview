import QtQuick
import QtQuick.Controls
import Quickshell
import "."

Scope {
    FloatingWindow {
        visible: true; implicitWidth: 600; implicitHeight: 300
        Item {
            id: host
            anchors.centerIn: parent; width: 80; height: 30
            readonly property string payload: '<img src="' + Quickshell.env('SCRATCHVIEW_TEST_URL') + '"><b>Window & title</b>'
            PlainToolTip {
                id: safeTip
                visible: Quickshell.env('SCRATCHVIEW_UNSAFE_CONTROL') !== '1'
                delay: 0
                text: parent.payload
            }
            Loader {
                active: Quickshell.env('SCRATCHVIEW_UNSAFE_CONTROL') === '1'
                sourceComponent: Component {
                    ToolTip {
                        visible: true
                        delay: 0
                        text: host.payload
                    }
                }
            }
            Timer {
                interval: 1800; running: true
                onTriggered: {
                    if (safeTip.contentItem.textFormat !== Text.PlainText || safeTip.contentItem.text !== parent.payload) {
                        console.error('PLAIN_TEXT_FAILED'); Qt.exit(2)
                    } else {
                        console.log('PLAIN_TEXT_OK'); Qt.quit()
                    }
                }
            }
        }
    }
}
