#!/usr/bin/env python3
"""Verify delayed and route-change-only remote source selection."""
import argparse
import json
import subprocess
import time
import urllib.parse


def osa(script):
    return subprocess.check_output(['osascript', '-e', script], timeout=35).decode().strip()


def wait(check, seconds=90):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(.25)
    raise AssertionError('Timed out')


def windows():
    return {int(value) for value in osa('tell application "QuickTime Player" to get id of every window').split(',') if value.strip()}


cases = [
    ('normal', {}),
    ('change-listener-only', {'routeChangeOnly': '1'}),
    ('slow-route', {'routeDelay': '7000'}),
]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('cases', nargs='*')
selected = parser.parse_args().cases
if any(name not in [case[0] for case in cases] for name in selected):
    parser.error('Unknown case')

for name, extra in cases:
    if selected and name not in selected:
        continue
    baseline = windows()
    query = dict(source='mse.mp4', airplay='route', test=str(time.time_ns()), **extra)
    url = 'http://127.0.0.1:8843/quicktime.html?' + urllib.parse.urlencode(query)
    osa('tell application "Safari" to make new document with properties {URL:' + json.dumps(url) + '}')
    wait(lambda: osa('tell application "Safari" to get URL of current tab of front window') == url)
    window_id = osa('tell application "Safari" to get id of front window')

    def js(script):
        return osa('tell application "Safari" to do JavaScript ' + json.dumps(script) + ' in current tab of window id ' + window_id)

    wait(lambda: js('Boolean(document.querySelector("#video")?.readyState>=2&&document.querySelector("#open-media-player"))') == 'true')
    js('video.play()')
    wait(lambda: float(js('video.currentTime')) > .5)
    started = time.monotonic()
    js('document.querySelector("#open-media-player").click()')
    result = json.loads(wait(lambda: (lambda text: text if text.startswith('{') else None)(js('document.querySelector("#media-player-result").textContent'))))
    print(name, round(time.monotonic() - started, 3), result, flush=True)
    print('state', js('JSON.stringify({src:video.currentSrc,wireless:video.webkitCurrentPlaybackTargetIsWireless,ready:video.readyState,error:video.error?.message})'), flush=True)
    assert result.get('method') == 'url', (name, result)
    owned = wait(lambda: windows() - baseline)
    assert len(owned) == 1, owned
    movie = 'document of window id ' + str(next(iter(owned)))

    def qt(command):
        return osa('tell application "QuickTime Player" to ' + command.replace('MOVIE', movie))

    osa('tell application "Safari" to close current tab of window id ' + window_id)
    before = float(qt('get current time of MOVIE'))
    wait(lambda: float(qt('get current time of MOVIE')) > before + 2, 15)
    qt('close MOVIE saving no')
    wait(lambda: windows() == baseline)
print('PASS remote route discovery and tab closure', flush=True)
