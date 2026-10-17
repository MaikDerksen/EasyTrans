"""Builds the timed voiceover for the "STOPP" TikTok and mixes it under the exported film.

Each line is synthesized separately (Microsoft Edge neural TTS via `edge-tts`), sped up slightly if
it would overrun its slot, and placed at the slot's start time, so the voice matches the captions.

    pip install edge-tts imageio-ffmpeg
    python voiceover.py                      # -> build/voiceover.mp3
    python voiceover.py film.mp4             # -> build/EasyTrans-TikTok-Stopp.mp4 (voice + music)
"""

import asyncio
import re
import subprocess
import sys
from pathlib import Path

import edge_tts
import imageio_ffmpeg

VOICE = "de-DE-AmalaNeural"
RATE = "+22%"
PITCH = "+2Hz"
TOTAL = 25.0
MUSIC_LEVEL = 0.35

# (start, end, text) — must match the caption timing in docs/marketing/tiktok-stopp.md
LINES = [
    (0.0, 1.5, "Stopp! Nicht weiterscrollen!"),
    (1.5, 4.0, "Du sitzt im Restaurant in Spanien – und verstehst kein Wort."),
    (4.0, 7.0, "Also tippst du alles in eine Übersetzer-App. Hin und her, hin und her …"),
    (7.0, 9.5, "… und das Essen ist kalt, bevor ihr fertig seid."),
    (9.5, 11.5, "Aber das hier ändert alles:"),
    (11.5, 15.0, "Handy auf den Tisch – und ihr redet einfach drauflos."),
    (15.0, 18.5, "Die App erkennt selbst, wer spricht, und übersetzt live."),
    (18.5, 21.5, "Du liest Deutsch, er liest Spanisch. Ganz ohne Knopfdrücken."),
    (21.5, 25.0, "Sie heißt EasyTrans. Speicher dir das für deinen nächsten Urlaub!"),
]

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
OUT = Path(__file__).resolve().parents[2] / "build"


def duration(path: Path) -> float:
    probe = subprocess.run([FFMPEG, "-i", str(path)], capture_output=True, text=True).stderr
    h, m, s = re.search(r"Duration: (\d+):(\d+):([\d.]+)", probe).groups()
    return int(h) * 3600 + int(m) * 60 + float(s)


async def synthesize(index: int, text: str) -> Path:
    raw = OUT / "voice" / f"line{index}-raw.mp3"
    await edge_tts.Communicate(text, VOICE, rate=RATE, pitch=PITCH).save(str(raw))
    # The service pads every clip with silence; trim both ends so lines sit tight on their cue.
    trim = "silenceremove=start_periods=1:start_threshold=-50dB"
    path = OUT / "voice" / f"line{index}.wav"
    subprocess.run(
        [FFMPEG, "-y", "-loglevel", "error", "-i", str(raw),
         "-af", f"{trim},areverse,{trim},areverse", str(path)],
        check=True,
    )
    return path


async def build_voiceover() -> Path:
    (OUT / "voice").mkdir(parents=True, exist_ok=True)
    clips = [await synthesize(i, text) for i, (_, _, text) in enumerate(LINES)]

    inputs, filters, labels = [], [], []
    for i, ((start, end, text), clip) in enumerate(zip(LINES, clips)):
        slot = end - start - 0.08
        length = duration(clip)
        tempo = min(max(length / slot, 1.0), 1.45)
        if length / slot > 1.45:
            print(f"warning: line {i} is {length:.2f}s for a {slot:.2f}s slot even at 1.45x: {text}")
        inputs += ["-i", str(clip)]
        filters.append(f"[{i}:a]atempo={tempo:.3f},adelay={int(start * 1000)}:all=1[v{i}]")
        labels.append(f"[v{i}]")
        print(f"line {i}: {length:.2f}s -> {length / tempo:.2f}s in {slot:.2f}s slot")

    filters.append(
        f"{''.join(labels)}amix=inputs={len(labels)}:normalize=0,"
        f"apad,atrim=0:{TOTAL},loudnorm=I=-14:TP=-1.5[out]"
    )
    voice = OUT / "voiceover.mp3"
    subprocess.run(
        [FFMPEG, "-y", "-loglevel", "error", *inputs, "-filter_complex", ";".join(filters),
         "-map", "[out]", "-ar", "48000", "-b:a", "192k", str(voice)],
        check=True,
    )
    return voice


def mix_into(film: Path, voice: Path) -> Path:
    out = OUT / "EasyTrans-TikTok-Stopp.mp4"
    has_audio = "Audio:" in subprocess.run([FFMPEG, "-i", str(film)], capture_output=True, text=True).stderr
    if has_audio:
        graph = (f"[0:a]volume={MUSIC_LEVEL}[m];[1:a]volume=1.0[v];"
                 f"[m][v]amix=inputs=2:duration=first:normalize=0[a]")
        audio = ["-filter_complex", graph, "-map", "0:v", "-map", "[a]"]
    else:
        audio = ["-map", "0:v", "-map", "1:a"]
    subprocess.run(
        [FFMPEG, "-y", "-loglevel", "error", "-i", str(film), "-i", str(voice), *audio,
         "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", str(out)],
        check=True,
    )
    return out


if __name__ == "__main__":
    voice = asyncio.run(build_voiceover())
    print(f"voiceover: {voice}")
    if len(sys.argv) > 1:
        print(f"video: {mix_into(Path(sys.argv[1]), voice)}")
