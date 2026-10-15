(function () {
    "use strict";
    var contextVideo;
    var contextID = 0;
    function visibleArea(video) {
        var rect = video.getBoundingClientRect();
        rect = { left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom };
        var node = video;
        var view = video.ownerDocument.defaultView;
        function clip(box, horizontal, vertical) {
            if (horizontal) {
                rect.left = Math.max(rect.left, box.left);
                rect.right = Math.min(rect.right, box.right);
            }
            if (vertical) {
                rect.top = Math.max(rect.top, box.top);
                rect.bottom = Math.min(rect.bottom, box.bottom);
            }
        }
        while (node) {
            var style = view.getComputedStyle(node);
            if (style.display === "none" || Number(style.opacity) === 0 || ((node === video || node.localName === "iframe" || node.localName === "frame") && style.visibility !== "visible"))
                return 0;
            if (node !== video)
                clip(node.getBoundingClientRect(), style.overflowX !== "visible", style.overflowY !== "visible");
            node = node.parentElement || (node.getRootNode().host || null);
            if (node)
                continue;
            clip({ left: 0, top: 0, right: view.innerWidth, bottom: view.innerHeight }, true, true);
            var frame = view.frameElement;
            if (!frame)
                break;
            var frameRect = frame.getBoundingClientRect();
            var scaleX = frame.offsetWidth ? frameRect.width / frame.offsetWidth : 1;
            var scaleY = frame.offsetHeight ? frameRect.height / frame.offsetHeight : 1;
            rect.left = frameRect.left + (frame.clientLeft + rect.left) * scaleX;
            rect.right = frameRect.left + (frame.clientLeft + rect.right) * scaleX;
            rect.top = frameRect.top + (frame.clientTop + rect.top) * scaleY;
            rect.bottom = frameRect.top + (frame.clientTop + rect.bottom) * scaleY;
            node = frame;
            view = frame.ownerDocument.defaultView;
        }
        return Math.max(0, rect.right - rect.left) * Math.max(0, rect.bottom - rect.top);
    }
    function videos(root, result) {
        Array.prototype.forEach.call(root.querySelectorAll("*"), function (element) {
            if (element.localName === "video")
                result.push(element);
            if (element.shadowRoot && element.shadowRoot.mode === "open")
                videos(element.shadowRoot, result);
            if (element.localName === "iframe" || element.localName === "frame") {
                try {
                    if (element.contentDocument)
                        videos(element.contentDocument, result);
                } catch (_) { }
            }
        });
        return result;
    }
    document.addEventListener("contextmenu", function (event) {
        var video = event.composedPath().find(function (element) { return element.localName === "video"; });
        if (!video)
            return;
        contextVideo = video;
        safari.self.tab.setContextMenuEventUserInfo(event, {
            quickTimeVideo: true, frame: browser.runtime.getFrameId(window), id: ++contextID
        });
    }, false);
    safari.self.addEventListener("message", function (event) {
        if (event.name !== "open")
            return;
        var info = event.message;
        var video;
        if (info && info.quickTimeVideo) {
            if (info.frame !== browser.runtime.getFrameId(window) || info.id !== contextID)
                return;
            video = contextVideo;
        } else {
            if (window !== window.top)
                return;
            video = videos(document, []).map(function (video) {
                return { video: video, area: visibleArea(video), playing: !video.paused && !video.ended };
            }).filter(function (item) { return item.area > 0; }).sort(function (a, b) {
                return Number(b.playing) - Number(a.playing) || b.area - a.area;
            }).map(function (item) { return item.video; })[0];
        }
        aqua.quickTimePlayer.open(video).then(function (result) {
            safari.self.tab.dispatchMessage("quicktime-result", result);
        }, function (error) {
            safari.self.tab.dispatchMessage("quicktime-result", { error: error.message });
        });
    }, false);
}());
