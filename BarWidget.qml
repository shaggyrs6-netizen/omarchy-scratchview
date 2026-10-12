import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: 'shaggyrs6.scratchview'
    // Resolve helpers beside this widget in any user's installed plugin folder.
    readonly property string sourceRoot: decodeURIComponent(Qt.resolvedUrl('.').toString().replace(/^file:\/\//, '')).replace(/\/$/, '')
    property int count: 0
    property bool healthy: true
    property string launchError: ''
    property var entries: []
    property string viewMode: 'panel'
    property bool undoAvailable: false
    property var selected: null
    property Item selectedAnchor: null
    readonly property bool strip: viewMode === 'bar' && !root.vertical
    readonly property int parkedCount: entries.filter(e => e.parked).length
    readonly property string summary: parkedCount + ' parked · ' + (count-parkedCount) + ' on desktop'
    readonly property bool opened: menu.open
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    function close() { menu.open = false }
    function refresh() { if (!reader.running && !worker.running) reader.running = true }
    function restore(target) {
        close()
        if (!launcher.running) { launchError = ''; launcher.command = ['python3',sourceRoot + '/control.py',target || 'restore']; launcher.running = true }
    }
    function accept(text) {
        try {
            const data = JSON.parse(text)
            healthy = data.ok === true
            if (!healthy) { launchError = data.error || 'ScratchView needs attention'; return }
            count = data.cards.length
            if (JSON.stringify(entries) !== JSON.stringify(data.cards)) entries = data.cards
            viewMode = data.settings.viewMode || 'panel'
            undoAvailable = data.undoAvailable === true
            if (selected) {
                const latest = entries.find(e => e.address === selected.address && e.identity === selected.identity)
                if (!latest) close()
                else selected = latest
            }
        } catch(e) { healthy = false }
    }
    function act(verb, entry) {
        close()
        if (worker.running) return
        launchError = ''
        worker.command = ['python3',sourceRoot + '/backend.py',verb,entry ? entry.address : '']
        if (entry) worker.command = worker.command.concat([entry.identity])
        worker.running = true
    }
    function showMenu(entry, anchor) { selected = entry; selectedAnchor = anchor; menu.open = true }
    Component.onCompleted: refresh()
    Timer { interval: 3000; running: true; repeat: true; onTriggered: root.refresh() }
    Process {
        id: reader
        command: ['python3', root.sourceRoot + '/backend.py', 'status']
        stdout: StdioCollector { onStreamFinished: if (!worker.running) root.accept(text) }
    }
    Process { id: worker; stdout: StdioCollector { onStreamFinished: root.accept(text) } }
    Process {
        id: launcher
        command: ['python3', root.sourceRoot + '/control.py']
        onExited: function(code) { if (code !== 0) root.launchError = 'Could not restore ScratchView. Try its application menu entry.' }
    }
    IpcHandler {
        target: 'scratchview-bar'
        function restore(): void { root.restore() }
        function status(): string { return JSON.stringify({count:root.count,healthy:root.healthy,error:root.launchError,viewMode:root.viewMode,width:root.width,undoAvailable:root.undoAvailable}) }
        function parkPicker(): void { root.restore('parkPicker') }
    }
    Row {
        id: row
        spacing: Style.space(2)
        WidgetButton {
            id: button
            bar: root.bar
            text: '▣' + (!root.healthy || root.launchError ? ' !' : !root.strip && root.count > 0 ? ' ' + root.count : '')
            // Do not pass backend errors into a host-controlled AutoText sink.
            tooltipText: root.launchError ? 'ScratchView needs attention — open the panel' : ('ScratchView — open panel\n' + root.summary + '\nRight-click for Settings')
            onPressed: function(b) { root.restore(b === Qt.RightButton ? 'settings' : 'restore') }
        }
        WidgetButton {
            visible: root.strip
            bar: root.bar; text: '+'
            tooltipText: 'Park a window…'
            onPressed: function(b) { if (b === Qt.LeftButton) root.restore('parkPicker') }
        }
        Repeater {
            model: root.strip ? root.entries.slice(0,2) : []
            Row {
                id: chip
                required property var modelData
                WidgetButton {
                    id: chipButton
                    bar: root.bar; text: chip.modelData.title || chip.modelData.app
                    labelVisible: false; fixedWidth: Style.space(105)
                    // The host bar tooltip may use AutoText. Own this title tooltip.
                    tooltipText: ''
                    PlainToolTip {
                        visible: chipButton.tooltipHovered
                        text: (chip.modelData.title || chip.modelData.app) + '\n' + (chip.modelData.parked ? 'Parked — click to bring here' : 'On desktop — click to focus')
                        foreground: chipButton.foreground; backgroundColor: Color.background; outline: Color.accent
                        font.family: chipButton.fontFamily
                    }
                    onPressed: function(b) {
                        if (b === Qt.RightButton) root.showMenu(chip.modelData,chipButton)
                        else if (b === Qt.LeftButton) root.act(chip.modelData.parked ? 'bring' : 'focus',chip.modelData)
                    }
                    Row {
                        anchors.centerIn: parent; spacing: Style.space(5)
                        property var entry: DesktopEntries.heuristicLookup(chip.modelData.app)
                        Image { id: icon; width: Style.space(16); height: width; source: parent.entry && parent.entry.icon ? Quickshell.iconPath(parent.entry.icon,true) : ''; fillMode: Image.PreserveAspectFit }
                        Text { visible: icon.status !== Image.Ready; text: '▣'; color: chipButton.foreground; font.pixelSize: Style.font.body }
                        Text { width: Style.space(70); text: chip.modelData.title || chip.modelData.app; textFormat: Text.PlainText; elide: Text.ElideRight; color: chipButton.foreground; font.family: chipButton.fontFamily; font.pixelSize: Style.font.body }
                    }
                    Rectangle { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: Style.space(20); height: Style.space(2); color: chipButton.foreground; visible: chip.modelData.parked }
                }
                WidgetButton { bar: root.bar; text: '⋮'; fixedWidth: Style.space(22); tooltipText: 'Window actions'; onPressed: root.showMenu(chip.modelData,chipButton) }
            }
        }
        WidgetButton { visible: root.strip && root.count > 2; bar: root.bar; text: '+' + (root.count-2) + ' more'; tooltipText: 'Show all scratchpad cards'; onPressed: root.restore() }
        WidgetButton { visible: root.undoAvailable; bar: root.bar; text: 'Undo'; tooltipText: 'Restore the last dismissed card'; onPressed: root.act('undo',null) }
    }
    PopupCard {
        id: menu
        bar: root.bar; owner: root
        anchorItem: root.selectedAnchor || button
        contentWidth: Style.space(270)
        contentHeight: Style.space(root.selected && !root.selected.parked ? 220 : 168)
        Column {
            anchors.fill: parent; spacing: Style.space(8)
            Text { width: parent.width; text: root.selected ? root.selected.title || root.selected.app : ''; textFormat: Text.PlainText; elide: Text.ElideRight; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
            Text { text: root.selected && root.selected.parked ? 'Parked' : 'On desktop'; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
            MenuAction { text: root.selected && root.selected.parked ? 'Bring here' : 'Put back'; onTriggered: if(root.selected) root.act(root.selected.parked ? 'bring' : 'return',root.selected) }
            MenuAction { visible: root.selected && !root.selected.parked; text: 'Dismiss card'; onTriggered: if(root.selected) root.act('dismiss',root.selected) }
            MenuAction { text: 'Open panel'; onTriggered: root.restore() }
        }
    }
    component MenuAction: Rectangle {
        property string text
        signal triggered()
        width: parent.width; height: Style.space(36); radius: Style.space(5)
        color: Qt.rgba(Color.foreground.r,Color.foreground.g,Color.foreground.b,hit.containsMouse ? 0.18 : 0.08)
        Text { anchors.centerIn: parent; text: parent.text; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
        MouseArea { id: hit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !worker.running; onClicked: parent.triggered() }
    }
}
