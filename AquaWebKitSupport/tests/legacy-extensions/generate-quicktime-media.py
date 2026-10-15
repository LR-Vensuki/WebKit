#!/usr/bin/env python3
"""Generate the local handoff fixtures with the vendored GStreamer runtime."""
import os
from pathlib import Path
import re
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
# MPEG-TS segments of at most 6 s, each starting at a keyframe, and their playlist. splitmuxsink reports
# each segment's duration as it closes it.
segmenter = subprocess.run([str(gst), '-m', '-e'] + (
    f'filesrc location={out / "plain.mp4"} ! qtdemux name=demux '
    f'splitmuxsink name=hls muxer=mpegtsmux location={out}/hls-%05d.ts max-size-time=6000000000 '
    'demux.video_0 ! queue ! h264parse ! hls.video '
    'demux.audio_0 ! queue ! aacparse ! hls.audio_0').split(), env=env, check=True, stdout=subprocess.PIPE,
    universal_newlines=True).stdout
segment_durations = [int(duration) / 1e9 for duration in
                     re.findall(r'splitmuxsink-fragment-closed, .*fragment-duration=\(guint64\)(\d+)', segmenter)]
with (out / 'index.m3u8').open('w') as playlist:
    playlist.write('#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-MEDIA-SEQUENCE:0\n')
    playlist.write(f'#EXT-X-TARGETDURATION:{max(round(duration + 0.5) for duration in segment_durations)}\n\n')
    for index, duration in enumerate(segment_durations):
        playlist.write(f'#EXTINF:{duration:.3f},\nhls-{index:05d}.ts\n')
    playlist.write('#EXT-X-ENDLIST\n')
for video, audio in [('vp9', 'opus'), ('vp8', 'vorbis')]:
    run(f'webmmux name=mux streamable=true ! filesink location={out}/{video}-{audio}.webm '
        'videotestsrc num-buffers=1800 pattern=ball ! video/x-raw,width=320,height=180,framerate=30/1 '
        f'! {video}enc deadline=1 keyframe-max-dist=60 ! queue ! mux.video_0 '
        'audiotestsrc num-buffers=2813 samplesperbuffer=1024 ! audio/x-raw,rate=48000,channels=2 '
        f'! {audio}enc ! queue ! mux.audio_0')
