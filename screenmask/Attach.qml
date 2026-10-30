import QtQuick 2.4

// Loaded inside the running compositor by com.webos.service.systemUIManager/launch
// (see loader.sh). This helper never shows a window and never takes focus. It
// walks up to the compositor root and creates Masks.qml there, above Views, so
// the masks survive app switches.
//
// Keep this helper alive: its creation context owns the masks' bindings and
// their Timer. If the helper is destroyed, the masks stop updating.
Item {
    id: helper
    visible: false
    enabled: false

    Component.onCompleted: {
        parent.windowSetProperty("needFocus", false);
        parent.windowSetProperty("keepWindowOnAppSwitch", true);

        var host = parent;
        while (host.parent) host = host.parent;

        var url = Qt.resolvedUrl("Masks.qml");
        var request = new XMLHttpRequest();
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE) return;
            // A re-attach (upgrade or recovery) replaces the previous masks.
            for (var i = host.children.length - 1; i >= 0; i--) {
                if (host.children[i].objectName === "orgFabsScreenmask") {
                    host.children[i].destroy();
                }
            }
            var masks = Qt.createQmlObject(request.responseText, host, url);
            masks.configUrl = "file://@STATE_DIR@/masks.conf";
            masks.ackUrl = "file://@ACK@";
        };
        request.open("GET", url);
        request.send();
    }
}
