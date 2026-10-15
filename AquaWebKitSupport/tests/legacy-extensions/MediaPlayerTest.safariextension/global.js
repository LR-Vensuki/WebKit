(function () {
    "use strict";
    var stored;
    var portTabs = new Map();
    browser.runtime.onConnect.addListener(function (port) {
        if (!port.name.startsWith("handoff-lifetime:"))
            return;
        var id = port.name.substring("handoff-lifetime:".length);
        port.onMessage.addListener(async function (message) {
            if (message === "ready") {
                var tab = portTabs.get(id);
                portTabs.delete(id);
                tab.close();
                var absent = false;
                try { absent = !(await browser.tabs.get(port.sender.tab.id)); }
                catch (error) { absent = true; }
                port.postMessage({ kind: "ping", absent: absent });
            } else if (message.kind === "pong") {
                report({ id: id, stage: "port-roundtrip", absent: message.absent });
                port.postMessage({ kind: "finish" });
            }
        });
        port.onDisconnect.addListener(function () { report({ id: id, stage: "port-disconnected" }); });
    });
    function report(value) {
        var request = new XMLHttpRequest();
        request.open("POST", "http://127.0.0.1:8843/handoff-dispatch-report", true);
        request.send(JSON.stringify(value));
    }
    safari.application.addEventListener("message", async function (event) {
        if (event.name !== "test-prepare-handoff")
            return;
        var tab = event.target, page = tab.page, message = event.message;
        try {
            if (message.mode === "busy-close")
                page.dispatchMessage("test-handoff-busy", 3000);
            var ticket = message.mode === "use-stored" ? stored : await aqua.mediaPlayer.prepareHandoff(tab);
            if (message.mode === "store") {
                stored = ticket;
                report({ id: message.id, stage: "stored" });
                return;
            }
            if (message.mode === "cancel")
                await aqua.mediaPlayer.cancelHandoff(ticket);
            if (message.mode === "expired")
                await new Promise(function (resolve) { setTimeout(resolve, 31000); });
            if (message.mode === "port-close")
                portTabs.set(message.id, tab);
            if (message.mode !== "unused-close")
                page.dispatchMessage("test-handoff-ticket", { id: message.id, mode: message.mode, ticket: ticket });
            if (message.mode.endsWith("close") && message.mode !== "port-close")
                tab.close();
            report({ id: message.id, stage: "dispatched" });
        } catch (error) {
            report({ id: message.id, stage: "error", error: error.message });
        }
    }, false);
}());
