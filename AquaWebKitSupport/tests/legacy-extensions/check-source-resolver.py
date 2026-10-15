#!/usr/bin/env python3
"""Exercise asynchronous extension source resolution and supplied HLS masters."""
import argparse
import json
import subprocess
import time
import urllib.request
import urllib.error


def osa(script):
    return subprocess.check_output(['osascript', '-e', script], timeout=40).decode().strip()


def js(script):
    return osa('tell application "Safari" to do JavaScript ' + json.dumps(script) + ' in current tab of front window')


def wait(check, seconds=90):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(.25)
    raise AssertionError('Timed out')


def windows():
    return {int(item) for item in osa('tell application "QuickTime Player" to get id of every window').split(',') if item.strip()}


def result():
    value = js('document.querySelector("#media-player-result").textContent')
    return json.loads(value) if value.startswith('{') else None


parser = argparse.ArgumentParser(description=__doc__)
all_modes = ['identity', 'playlist', 'reject', 'invalid', 'oversized', 'timeout', 'delay', 'timeout-replaced']
parser.add_argument('modes', nargs='*', default=all_modes)
modes = parser.parse_args().modes
if any(mode not in all_modes for mode in modes):
    parser.error('Unknown resolver mode')
baseline = windows()
for mode in modes:
    source_parameters = 'mse.mp4&airplay=route' if mode in ['delay', 'timeout-replaced'] else 'index.m3u8'
    url = 'http://127.0.0.1:8843/quicktime.html?source=' + source_parameters + '&resolve=' + mode
    osa('tell application "Safari" to make new document with properties {URL:' + json.dumps(url) + '}')
    wait(lambda: js('Boolean(document.querySelector("video")?.readyState >= 2 && document.querySelector("#open-media-player"))') == 'true')
    js('video.currentTime=5;video.play()')
    wait(lambda: js('!video.seeking && video.currentTime>=5') == 'true')
    source = js('video.currentSrc')
    js('document.querySelector("#open-media-player").click()')
    if mode in ['delay', 'timeout-replaced']:
        wait(lambda: js('document.querySelector("#media-player-result").dataset.resolving') == 'true')
        js('video.src="/quicktime-media/plain.mp4?replacement";video.load()')
    value = wait(result)
    print(mode, value, flush=True)
    if mode in ['identity', 'playlist']:
        assert value['method'] == 'url', value
        if mode == 'identity':
            assert value['url'] == source, value
        else:
            assert value['url'] != source, value
            text = urllib.request.urlopen(value['url'], timeout=10).read().decode()
            assert source in text and '#EXT-X-STREAM-INF:' in text, text
        owned = wait(lambda: windows() - baseline)
        assert len(owned) == 1, owned
        movie = 'document of window id ' + str(next(iter(owned)))
        def qt(command):
            return osa('tell application "QuickTime Player" to ' + command.replace('MOVIE', movie))
        wait(lambda: float(qt('get duration of MOVIE')) >= 55)
        qt('set current time of MOVIE to 30')
        qt('play MOVIE')
        wait(lambda: float(qt('get current time of MOVIE')) >= 30)
        osa('tell application "Safari" to close current tab of front window')
        start = float(qt('get current time of MOVIE'))
        wait(lambda: float(qt('get current time of MOVIE')) > start + 4)
        qt('close MOVIE saving no')
        wait(lambda: windows() == baseline)
        if mode == 'playlist':
            def released():
                try:
                    urllib.request.urlopen(value['url'], timeout=2).close()
                    return False
                except (urllib.error.URLError, ConnectionError):
                    return True
            wait(released)
    else:
        assert value.get('error') == ('no-source' if mode in ['delay', 'timeout-replaced'] else 'source-resolution-failed'), value
        assert windows() == baseline, 'Resolver failure opened a receiver'
        osa('tell application "Safari" to close current tab of front window')
print('PASS source resolution, full seek, tab closure, cleanup and error paths', flush=True)
