#!/usr/bin/env python3
"""Original, deterministic game audio, generated without samples or recordings."""
from pathlib import Path
import math
import wave
import array

OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"
RATE = 22050


def write(name, samples):
    samples = array.array("h", (round(max(-1, min(1, x)) * 32767) for x in samples))
    with wave.open(str(OUT / name), "wb") as out:
        out.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        out.writeframes(samples.tobytes())


def note(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def effect(name, notes, length=0.25):
    result = []
    for i in range(int(RATE * length)):
        t = i / RATE
        u = t / length
        freq = note(notes[min(len(notes)-1, int(u * len(notes)))])
        envelope = min(1, t / 0.008) * (1 - u) ** 2
        result.append((math.sin(2*math.pi*freq*t) + .15*math.sin(4*math.pi*freq*t)) * envelope * .28)
    write(name + ".wav", result)


def music(stage):
    # Continuous twelve-second loops, with increasingly close intervals and
    # faster arpeggios. No percussive low-frequency pulse/heartbeat.
    chords = [(45, 52, 57, 60), (41, 48, 53, 57), (43, 50, 55, 58), (40, 47, 52, 55)]
    if stage == 2:
        chords = [(45, 52, 58, 60), (41, 48, 54, 57), (43, 50, 56, 58), (40, 47, 53, 55)]
    elif stage == 3:
        chords = [(45, 51, 58, 60), (41, 47, 54, 57), (43, 49, 56, 58), (40, 46, 53, 55)]
    result = []
    for i in range(RATE * 12):
        t = i / RATE
        chord = chords[min(3, int(t / 3))]
        local = t % 3
        # A soft pad swells at the edges of each harmony; no samples used.
        env = min(1, local / .18, (3-local) / .35)
        pad = sum(math.sin(2*math.pi*note(n)*t) for n in chord) / 4
        interval = [.75, .5, .25][stage-1]
        phase = t % interval
        melody = note(chord[int(t/interval) % 4] + 24)
        bell = math.sin(2*math.pi*melody*t) * math.exp(-phase*8) * min(1,phase/.006)
        endfade = min(1,t/.06,(12-t)/.06)
        result.append((pad*.14*env + bell*.09)*endfade)
    write(f"music_{stage}.wav", result)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for stage in (1, 2, 3):
        music(stage)
    for name, notes, length in [
        ("click", [74], .07), ("collect", [79, 86], .17),
        ("feed", [60, 64, 67], .28), ("wash", [86, 89, 93], .32),
        ("pet", [72, 76], .20), ("sleep", [72, 67, 64], .45),
        ("egg", [72, 76, 79, 84], .60), ("hatch", [67, 72, 76, 79, 84], .70),
        ("move", [67, 74, 79], .35), ("win", [60, 64, 67, 72, 76], 1.0),
        ("loss", [67, 63, 60, 55], 1.0)]:
        effect(name, notes, length)
    print("Generated 3 original music loops and 11 original effects.")

