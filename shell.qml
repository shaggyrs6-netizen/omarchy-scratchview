import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "Visibility.js" as Visibility

Scope {
    id: root
    property var entries: []
    property color bg: '#171723'
    property color fg: '#f3f0e9'
    property color accent: '#2dd4bf'
    property color muted: '#a8a8b8'
    property string fontFamily: 'monospace'
    property string error: ''
    property bool loaded: false
    property bool collapsed: false
    property bool explicitRestore: Quickshell.env('SCRATCHVIEW_RESTORE') === '1'
    property bool settingsOpen: false
    property bool pickerOpen: false
    property var candidates: []
    property bool undoAvailable: false
    property bool pendingEmpty: false
    property string viewMode: 'panel'
    property string displayMode: 'preview'
    readonly property bool compact: displayMode === 'compact'
    property int px: 40
    property int py: 90
    property int pw: 360
    property int ph: 660
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl('backend.py').toString().replace(/^file:\/\//, ''))
    function accept(text) {
        try {
            const data = JSON.parse(text)
            if (!data.ok) { error = data.error || 'Could not read scratchpad'; return }
            if (!data.cards) return
            undoAvailable = data.undoAvailable === true
            if (Visibility.shouldHide(!loaded, entries.length, data.cards.length, explicitRestore)) pendingEmpty = true
            if (data.cards.length > 0) pendingEmpty = false
            if (pendingEmpty && !undoAvailable && !pickerOpen && !settingsOpen) { collapsed = true; pendingEmpty = false }
            if (data.candidates) candidates = data.candidates
            // Avoid destroying live previews on every refresh.
            if (JSON.stringify(entries) !== JSON.stringify(data.cards)) entries = data.cards
            bg = data.theme.background; fg = data.theme.foreground
            accent = data.theme.accent; muted = data.theme.muted
            if (!loaded) {
                px = data.geometry.x; py = data.geometry.y
                pw = data.geometry.width; ph = data.geometry.height
                displayMode = data.settings ? data.settings.displayMode : 'preview'
                loaded = true
            }
            if (!modeTimer.running && !modeSaver.running && data.settings) viewMode = data.settings.viewMode || 'panel'
            error = ''
        } catch(e) { error = 'Unable to read ScratchView data' }
    }
    function refresh() { if (!reader.running && !worker.running) reader.running = true; Hyprland.refreshToplevels() }
    function act(verb, address, token) {
        if (worker.running) return
        worker.lastVerb = verb
        worker.command = ['python3', helper, verb, address || '']
        if (token) worker.command = worker.command.concat([token])
        worker.running = true
    }
    function activate(entry) { act(entry.parked ? 'bring' : 'focus', entry.address, entry.identity) }
    function showPicker() { explicitRestore = true; pendingEmpty = false; collapsed = false; settingsOpen = false; pickerOpen = true; refresh() }
    function save() { saveTimer.restart() }
    function setMode(mode) {
        if (mode !== 'preview' && mode !== 'compact') return
        displayMode = mode
        modeTimer.restart()
    }
    function setView(mode) {
        if (mode !== 'panel' && mode !== 'bar') return
        viewMode = mode; modeTimer.restart()
    }
    Component.onCompleted: refresh()
    Timer { interval: root.collapsed ? 3000 : 1500; running: true; repeat: true; onTriggered: root.refresh() }
    Timer { id: saveTimer; interval: 300; onTriggered: {
        if (saver.running) { restart(); return }
        saver.command = ['python3', root.helper, 'geometry', JSON.stringify({x: root.px,y: root.py,width: root.pw,height: root.ph})]
        saver.running = true
    } }
    Process { id: saver }
    Timer { id: modeTimer; interval: 100; onTriggered: {
        if (modeSaver.running) { restart(); return }
        modeSaver.command = ['python3', root.helper, 'settings', JSON.stringify({displayMode: root.displayMode,viewMode: root.viewMode})]
        modeSaver.running = true
    } }
    Process { id: modeSaver; stdout: StdioCollector { onStreamFinished: {
        try { const result = JSON.parse(text); if (!result.ok) root.error = result.error } catch(e) { root.error = 'Could not save display setting' }
    } } }
    Process { id: fontReader; running: true; command: ['fc-match','-f','%{family[0]}','monospace']; stdout: StdioCollector { onStreamFinished: if (text.trim()) root.fontFamily = text.trim() } }
    Process { id: reader; command: ['python3',root.helper,root.pickerOpen ? 'picker' : 'status']; stdout: StdioCollector { onStreamFinished: if (!worker.running) root.accept(text) } }
    Process { id: worker; property string lastVerb: ''; stdout: StdioCollector { onStreamFinished: {
        root.accept(text)
        try { if (JSON.parse(text).ok && worker.lastVerb === 'park') root.pickerOpen = false } catch(e) {}
    } } }
    IpcHandler {
        target: 'scratchview'
        function quit(): void { Qt.quit() }
        function collapse(): void { root.collapsed = !root.collapsed }
        function restore(): void { root.explicitRestore = true; root.pendingEmpty = false; root.collapsed = false; root.pickerOpen = false; root.settingsOpen = false; root.refresh() }
        function parkPicker(): void { root.showPicker() }
        function settings(): void { root.explicitRestore = true; root.pendingEmpty = false; root.collapsed = false; root.pickerOpen = false; root.settingsOpen = true; root.refresh() }
        function view(value: string): void { root.setView(value) }
        function hide(): void { root.collapsed = true }
        function mode(value: string): void { root.setMode(value) }
        function geometry(x: int,y: int,w: int,h: int): void {
            root.px = Math.max(0,x); root.py = Math.max(0,y)
            root.pw = Math.max(200,Math.min(1000,w)); root.ph = Math.max(240,Math.min(1400,h)); root.save()
        }
        function status(): string { return JSON.stringify({count:root.entries.length,error:root.error,collapsed:root.collapsed,displayMode:root.displayMode,viewMode:root.viewMode,picker:root.pickerOpen,undoAvailable:root.undoAvailable,width:panel.width,height:panel.height}) }
    }
    PanelWindow {
        id: panel
        visible: !root.collapsed
        screen: Quickshell.screens.find(s => s.name === (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : '')) || Quickshell.screens[0]
        anchors { left: true; top: true }
        margins.left: Math.max(0, Math.min(root.px, screen.width - width))
        margins.top: Math.max(0, Math.min(root.py, screen.height - height))
        implicitWidth: Math.min(root.pw, screen.width)
        implicitHeight: Math.min(root.ph, screen.height)
        color: 'transparent'
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: 'omarchy-scratchview'
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Rectangle {
            anchors.fill: parent; radius: 12; color: root.bg; border.color: root.accent; border.width: 1
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 12; spacing: 10
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: 36; Layout.maximumHeight: 36; Layout.minimumHeight: 36
                    Item {
                        Layout.fillWidth: true; Layout.preferredHeight: 36
                        Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width; elide: Text.ElideRight; text: 'ScratchView'; color: root.fg; font.family: root.fontFamily; font.pixelSize: 14; font.bold: true }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.SizeAllCursor
                            property point start; property int ox; property int oy
                            onPressed: function(mouse) { start = mapToGlobal(mouse.x,mouse.y); ox = panel.margins.left; oy = panel.margins.top }
                            onPositionChanged: function(mouse) { if (pressed) {
                                const p = mapToGlobal(mouse.x,mouse.y)
                                root.px = Math.round(Math.max(0,Math.min(panel.screen.width-panel.width,ox+p.x-start.x)))
                                root.py = Math.round(Math.max(0,Math.min(panel.screen.height-panel.height,oy+p.y-start.y)))
                            } }
                            onReleased: root.save()
                            onDoubleClicked: root.collapsed = !root.collapsed
                        }
                    }
                    MiniButton { visible: !root.collapsed; text: '⚙'; onClicked: { root.settingsOpen = !root.settingsOpen; root.pickerOpen = false } ToolTip.visible: hovered; ToolTip.text: 'Settings'; Accessible.name: 'Settings' }
                    MiniButton { text: '−'; onClicked: root.collapsed = true; ToolTip.visible: hovered; ToolTip.text: 'Tuck away to the bar' }
                }
                Flickable {
                    visible: root.settingsOpen; Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    contentHeight: preferences.implicitHeight
                    Column {
                        id: preferences; width: parent.width; spacing: 8
                        Text { text: 'VIEW'; color: root.fg; font.family: root.fontFamily; font.pixelSize: 12 }
                        MiniButton { width: parent.width; text: (root.viewMode === 'panel' ? '✓ ' : '') + 'Floating panel'; onClicked: root.setView('panel') }
                        MiniButton { width: parent.width; text: (root.viewMode === 'bar' ? '✓ ' : '') + 'Horizontal bar'; onClicked: root.setView('bar') }
                        Text { width: parent.width; wrapMode: Text.Wrap; text: 'The panel stays available in either view.'; color: root.muted; font.family: root.fontFamily; font.pixelSize: 12 }
                        Text { text: 'PANEL CARDS'; color: root.fg; font.family: root.fontFamily; font.pixelSize: 12 }
                        MiniButton { width: parent.width; text: (root.compact ? '' : '✓ ') + 'Preview cards'; onClicked: root.setMode('preview') }
                        MiniButton { width: parent.width; text: (root.compact ? '✓ ' : '') + 'Compact list'; onClicked: root.setMode('compact') }
                        MiniButton { width: parent.width; text: 'Done'; onClicked: root.settingsOpen = false }
                        MiniButton { width: parent.width; text: 'Quit ScratchView'; onClicked: Qt.quit() }
                    }
                }
                MiniButton { visible: !root.settingsOpen; Layout.fillWidth: true; text: root.pickerOpen ? 'Back to scratchpad' : '+ Park a window…'; onClicked: root.pickerOpen ? root.pickerOpen = false : root.showPicker() }
                Text { visible: !root.settingsOpen; Layout.fillWidth: true; text: root.error || (root.pickerOpen ? 'Choose a window to park' : root.entries.filter(e => e.parked).length + ' parked · ' + root.entries.filter(e => !e.parked).length + ' on desktop'); wrapMode: Text.Wrap; color: root.error ? root.accent : root.fg; font.family: root.fontFamily; font.pixelSize: 12; textFormat: Text.PlainText }
                MiniButton { visible: root.undoAvailable && !root.settingsOpen; Layout.fillWidth: true; text: 'Card dismissed · Undo'; onClicked: root.act('undo','') }
                ListView {
                    id: picker
                    visible: root.pickerOpen && !root.settingsOpen; Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true; spacing: 8; model: root.candidates
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        required property var modelData
                        width: picker.width - 10; height: 128; radius: 8
                        color: Qt.rgba(root.fg.r,root.fg.g,root.fg.b,0.07)
                        ColumnLayout { anchors.fill: parent; anchors.margins: 10; spacing: 5
                            Text { Layout.fillWidth: true; text: modelData.title || modelData.app; textFormat: Text.PlainText; color: root.fg; font.family: root.fontFamily; font.pixelSize: 14; maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: modelData.app + ' · desktop ' + modelData.workspace; textFormat: Text.PlainText; color: root.muted; font.family: root.fontFamily; font.pixelSize: 11; elide: Text.ElideRight }
                            MiniButton { Layout.fillWidth: true; text: 'Park this window'; enabled: !worker.running; onClicked: root.act('park',modelData.address,modelData.identity) }
                        }
                    }
                    Text { anchors.centerIn: parent; width: parent.width; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; visible: root.candidates.length === 0; text: 'No desktop windows available to park.'; color: root.fg; font.family: root.fontFamily; font.pixelSize: 13 }
                }
                ListView {
                    id: list
                    visible: !root.collapsed && !root.pickerOpen && !root.settingsOpen; Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true; spacing: 10; model: root.entries
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        width: list.width - 12; height: (root.compact ? 106 : 242) + (modelData.parked ? 0 : 40); radius: 8
                        color: Qt.rgba(root.fg.r,root.fg.g,root.fg.b,0.06)
                        border.color: Qt.rgba(root.fg.r,root.fg.g,root.fg.b,0.18)
                        readonly property var windowSource: Hyprland.toplevels.values.find(t => ('0x' + t.address.replace(/^0x/,'')) === modelData.address) || null
                        readonly property var desktopEntry: DesktopEntries.heuristicLookup(modelData.app)
                        readonly property string displayTitle: modelData.title || (desktopEntry ? desktopEntry.name : modelData.app) || 'Untitled window'
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 10; spacing: 6
                            Text { visible: !root.compact; Layout.fillWidth: true; text: card.desktopEntry ? card.desktopEntry.name : (card.modelData.app || 'Application'); color: root.accent; font.pixelSize: 13; font.bold: true; font.family: root.fontFamily; elide: Text.ElideRight; textFormat: Text.PlainText }
                            Item {
                                Layout.fillWidth: true; Layout.preferredHeight: root.compact ? 28 : 18
                                RowLayout {
                                    anchors.fill: parent; spacing: 8
                                    Item {
                                        visible: root.compact; Layout.preferredWidth: 24; Layout.preferredHeight: 24
                                        Image { id: appIcon; anchors.fill: parent; source: card.desktopEntry && card.desktopEntry.icon ? Quickshell.iconPath(card.desktopEntry.icon, true) : ''; fillMode: Image.PreserveAspectFit }
                                        Text { anchors.centerIn: parent; visible: appIcon.status !== Image.Ready; text: '▣'; color: root.accent; font.pixelSize: 22 }
                                    }
                                    Text { Layout.fillWidth: true; text: card.displayTitle; color: root.fg; font.pixelSize: 14; font.family: root.fontFamily; elide: Text.ElideRight; textFormat: Text.PlainText }
                                }
                                MouseArea { id: titleMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !worker.running; onClicked: root.activate(card.modelData) }
                                ToolTip.visible: titleMouse.containsMouse
                                ToolTip.text: card.displayTitle
                            }
                            Item {
                                visible: !root.compact; Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                ScreencopyView { id: capture; anchors.fill: parent; captureSource: !root.collapsed && !root.compact && card.windowSource ? card.windowSource.wayland : null; live: false; paintCursor: false }
                                Timer { interval: 2000; running: !root.collapsed && !root.compact; repeat: true; onTriggered: capture.captureFrame() }
                                Column { anchors.centerIn: parent; visible: !capture.hasContent; spacing: 4
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: '▣'; color: root.accent; font.pixelSize: 32 }
                                    Text { text: 'Preview unavailable'; color: root.muted; font.family: root.fontFamily; font.pixelSize: 11 }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: !worker.running; onClicked: root.activate(card.modelData) }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: card.modelData.parked ? 'Parked' : 'On desktop'; color: root.fg; font.pixelSize: 12; font.family: root.fontFamily; Layout.fillWidth: true; Layout.preferredWidth: 40; wrapMode: Text.WordWrap }
                                MiniButton { text: card.modelData.parked ? 'Bring here' : 'Put back'; enabled: !worker.running; onClicked: root.act(card.modelData.parked ? 'bring' : 'return',card.modelData.address,card.modelData.identity) }
                            }
                            MiniButton {
                                    visible: !card.modelData.parked
                                    Layout.fillWidth: true
                                    text: 'Dismiss card'
                                    enabled: !worker.running
                                    Accessible.name: 'Dismiss card without closing window'
                                    ToolTip.visible: hovered
                                    ToolTip.text: 'Dismiss card — leave the window open'
                                    onClicked: root.act('dismiss', card.modelData.address, card.modelData.identity)
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent; width: parent.width - 20; visible: root.entries.length === 0
                        text: 'Your scratchpad is empty.\n\nClick “Park a window…” above\nto choose what to put away.'
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; color: root.muted; font.family: root.fontFamily; font.pixelSize: 13
                    }
                }
                Text { visible: !root.collapsed; Layout.fillWidth: true; wrapMode: Text.Wrap; text: 'Drag header to move · corner to resize'; color: root.muted; font.family: root.fontFamily; font.pixelSize: 10 }
            }
            MouseArea {
                visible: !root.collapsed; width: 24; height: 24; anchors.right: parent.right; anchors.bottom: parent.bottom; cursorShape: Qt.SizeFDiagCursor
                property point start; property int ow; property int oh
                onPressed: function(mouse) { start = mapToGlobal(mouse.x,mouse.y); ow = root.pw; oh = root.ph }
                onPositionChanged: function(mouse) { if (pressed) { const p = mapToGlobal(mouse.x,mouse.y); root.pw = Math.round(Math.max(200,Math.min(1000,ow+p.x-start.x))); root.ph = Math.round(Math.max(240,Math.min(1400,oh+p.y-start.y))) } }
                onReleased: root.save()
                Text { anchors.centerIn: parent; text: '◢'; color: root.accent; font.pixelSize: 13 }
            }
        }
    }
    component MiniButton: Rectangle {
        property string text
        readonly property bool hovered: mouse.containsMouse
        signal clicked()
        implicitWidth: Math.max(34,label.implicitWidth+16); implicitHeight: 36; radius: 5
        color: mouse.containsMouse ? Qt.rgba(root.accent.r,root.accent.g,root.accent.b,0.25) : Qt.rgba(root.fg.r,root.fg.g,root.fg.b,0.09)
        opacity: enabled ? 1 : 0.5
        Text { id: label; anchors.centerIn: parent; text: parent.text; color: root.fg; font.family: root.fontFamily; font.pixelSize: 13 }
        MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }
}
