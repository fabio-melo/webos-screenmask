import QtQuick 2.4

// Created by Attach.qml on the compositor root, above Views. Draws one
// rectangle per mask in masks.conf. Never takes focus or input.
//
// Every second it re-reads the config and writes a heartbeat ACK. The CLI uses
// the ACK revision to confirm a change. The loader uses the ACK age and build
// to decide whether it must re-attach.
Item {
    id: root
    objectName: "orgFabsScreenmask"
    anchors.fill: parent
    z: 1000000
    enabled: false

    property string build: "@BUILD@"
    property string configUrl: ""
    property string ackUrl: ""
    property string revision: ""
    property bool active: false
    property bool previewing: false
    property real previewUntil: 0
    property real ratio: 0.5        // compositor pixels per panel pixel
    property var masks: []

    // BEGIN parse — pure functions, also exercised by tests/parse.test.js
    function parseConfig(text) {
        var config = {enabled: false, revision: "", panelWidth: 3840,
                      panelHeight: 2160, previewUntil: 0, masks: []};
        var edges = {top: true, bottom: true, left: true, right: true};
        var lines = String(text).split("\n");
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line === "" || line.charAt(0) === "#") continue;
            var pair = /^([a-z_]+)=(.*)$/.exec(line);
            if (pair) {
                var key = pair[1], value = pair[2].trim();
                if (key === "enabled") config.enabled = value === "1";
                else if (key === "revision") config.revision = value;
                else if (key === "preview_until") config.previewUntil = parseInt(value, 10) || 0;
                else if (key === "panel") {
                    var panel = /^(\d+)x(\d+)$/.exec(value);
                    if (panel && +panel[1] > 0 && +panel[2] > 0) {
                        config.panelWidth = +panel[1];
                        config.panelHeight = +panel[2];
                    }
                }
                continue;
            }
            var f = line.split(/\s+/);
            if (f[0] !== "mask" || f.length < 7) continue;
            var uint = /^\d+$/;
            if (!edges[f[2]] || !uint.test(f[3]) || !uint.test(f[4]) || !uint.test(f[5])) continue;
            if (+f[3] === 0 || !/^#[0-9a-fA-F]{6}$/.test(f[6])) continue;
            config.masks.push({id: f[1], edge: f[2], size: +f[3], start: +f[4],
                               length: +f[5], color: f[6]});
        }
        return config.revision ? config : null;
    }

    // Converts a mask in panel pixels to a rectangle in compositor pixels.
    // Thickness rounds up, so a mask never covers less than it was asked to.
    function geometry(mask, ratio, width, height) {
        var thickness = Math.max(1, Math.ceil(mask.size * ratio));
        var start = Math.floor(mask.start * ratio);
        var horizontal = mask.edge === "top" || mask.edge === "bottom";
        var span = horizontal ? width : height;
        var length = mask.length > 0 ? Math.ceil(mask.length * ratio) : span - start;
        length = Math.max(0, Math.min(length, span - start));
        thickness = Math.min(thickness, horizontal ? height : width);
        if (mask.edge === "top") return {x: start, y: 0, width: length, height: thickness};
        if (mask.edge === "bottom") return {x: start, y: height - thickness, width: length, height: thickness};
        if (mask.edge === "left") return {x: 0, y: start, width: thickness, height: length};
        return {x: width - thickness, y: start, width: thickness, height: length};
    }
    // END parse

    function writeAck() {
        var ack = new XMLHttpRequest();
        ack.open("PUT", root.ackUrl);
        ack.send(JSON.stringify({app: "org.fabs.screenmask", build: root.build,
            revision: root.revision, enabled: root.active, masks: root.masks.length,
            previewing: root.previewing, width: root.width, height: root.height,
            updatedAt: Date.now()}));
    }

    function refresh() {
        if (!root.configUrl) return;
        var request = new XMLHttpRequest();
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE) return;
            var config = null;
            try {
                config = root.parseConfig(request.responseText);
            } catch (e) {
                // Keep the last valid state while the file is unreadable.
            }
            if (config) {
                if (config.revision !== root.revision) {
                    root.masks = config.masks;
                    root.revision = config.revision;
                }
                root.active = config.enabled;
                root.previewUntil = config.previewUntil;
                if (root.height > 0) root.ratio = root.height / config.panelHeight;
            }
            root.previewing = Date.now() < root.previewUntil * 1000;
            root.writeAck();
        };
        request.open("GET", root.configUrl);
        request.send();
    }

    Repeater {
        model: root.active || root.previewing ? root.masks : []
        Rectangle {
            property var box: root.geometry(modelData, root.ratio, root.width, root.height)
            x: box.x
            y: box.y
            width: box.width
            height: box.height
            color: root.previewing ? "#ff0000" : modelData.color
            enabled: false
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
