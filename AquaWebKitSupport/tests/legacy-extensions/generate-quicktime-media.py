#!/usr/bin/env python3
"""Generate the local handoff fixtures with the vendored GStreamer runtime."""
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[3]
gst = root / 'AquaWebKitSupport/deps/build/bin/gst-launch-1.0'
out = Path(__file__).resolve().parent / 'build/quicktime-media'
out.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, GST_REGISTRY_FORK='no')

def run(pipeline):
    subprocess.run([str(gst), '-e'] + pipeline.split(), env=env, check=True)

for filename, mux in [('plain.mp4', 'mp4mux'), ('mse.mp4', 'mp4mux fragment-duration=2000 streamable=true')]:
    run(f'{mux} name=mux ! filesink location={out / filename} '
        'videotestsrc num-buffers=1800 pattern=ball ! video/x-raw,format=NV12,width=320,height=180,framerate=30/1 '
        '! vtenc_h264 max-keyframe-interval=60 ! h264parse ! queue ! mux.video_0 '
        'audiotestsrc num-buffers=2813 samplesperbuffer=1024 ! audio/x-raw,rate=48000,channels=2 '
        '! fdkaacenc bitrate=128000 ! aacparse ! queue ! mux.audio_0')
run(f'filesrc location={out / "plain.mp4"} ! qtdemux name=demux '
    f'hlssink2 name=hls location={out}/hls-%05d.ts playlist-location={out}/index.m3u8 '
    'target-duration=6 max-files=0 playlist-length=0 '
    'demux.video_0 ! queue ! h264parse ! hls.video '
    'demux.audio_0 ! queue ! aacparse ! hls.audio')
for video, audio in [('vp9', 'opus'), ('vp8', 'vorbis')]:
    run(f'webmmux name=mux streamable=true ! filesink location={out}/{video}-{audio}.webm '
        'videotestsrc num-buffers=1800 pattern=ball ! video/x-raw,width=320,height=180,framerate=30/1 '
        f'! {video}enc deadline=1 keyframe-max-dist=60 ! queue ! mux.video_0 '
        'audiotestsrc num-buffers=2813 samplesperbuffer=1024 ! audio/x-raw,rate=48000,channels=2 '
        f'! {audio}enc ! queue ! mux.audio_0')
