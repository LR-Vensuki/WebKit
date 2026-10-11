(function () {
    "use strict";
    var command = "send-to-quicktime";
    safari.application.addEventListener("command", function (event) {
        if (event.command !== command)
            return;
        var tab = event.target && event.target.page ? event.target : safari.application.activeBrowserWindow.activeTab;
        if (tab && tab.page)
            tab.page.dispatchMessage("open", event.userInfo || null);
    }, false);
    safari.application.addEventListener("contextmenu", function (event) {
        if (event.userInfo && event.userInfo.quickTimeVideo)
            event.contextMenu.appendContextMenuItem(command, "Open Video in QuickTime Player", command);
    }, false);
    safari.application.addEventListener("message", function (event) {
        if (event.name !== "quicktime-result")
            return;
        var error = event.message.error;
        safari.extension.toolbarItems.forEach(function (item) {
            if (item.identifier !== command || item.browserWindow.activeTab !== event.target)
                return;
            item.badge = error ? 1 : 0;
            item.toolTip = error || "Open Video in QuickTime Player";
        });
    }, false);
}());
