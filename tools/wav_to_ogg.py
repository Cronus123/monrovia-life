"""Converts the long music and ambience loops in proto3d/audio from .wav to Ogg Vorbis.

Blender's bundled FFmpeg does the encoding (no other encoder needed):
    "<Blender>\\blender.exe" --background --factory-startup --python tools\\wav_to_ogg.py

The short sound effects stay .wav (Godot compresses them on import, and they must start
instantly). The game loads <name>.ogg when it exists, else <name>.wav (proto3d/game/game_audio.gd).
Run it again after tools/make_audio.py regenerates the sounds, then delete the long .wav files.
"""
import os
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO = os.path.join(HERE, "..", "proto3d", "audio")
LONG = ["amb_city_day", "amb_city_night", "amb_market", "amb_waves", "amb_rain", "music_menu",
        "radio_highlife", "radio_hipco", "radio_palmwine", "radio_bigtalk"]
BITRATE = 48  # kbit/s, mono 22.05 kHz

scene = bpy.context.scene
scene.render.fps = 1000              # 1 ms frames: the loop length is kept to the millisecond
scene.render.ffmpeg.audio_mixrate = 22050
scene.render.ffmpeg.audio_channels = "MONO"
if not scene.sequence_editor:
    scene.sequence_editor_create()
for name in LONG:
    src = os.path.join(AUDIO, name + ".wav")
    if not os.path.exists(src):
        print("skip (no wav):", name)
        continue
    seqs = scene.sequence_editor.sequences
    for s in list(seqs):
        seqs.remove(s)
    strip = seqs.new_sound(name, src, 1, 1)
    scene.frame_start = 1
    scene.frame_end = strip.frame_final_end - 1
    dst = os.path.join(AUDIO, name + ".ogg")
    bpy.ops.sound.mixdown(filepath=dst, check_existing=False, relative_path=False, container="OGG",
                          codec="VORBIS", format="S16", bitrate=BITRATE, split_channels=False)
    print("%s: %d -> %d bytes" % (name, os.path.getsize(src), os.path.getsize(dst)))
