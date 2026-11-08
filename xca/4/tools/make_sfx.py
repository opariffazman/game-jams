#!/usr/bin/env python3
"""Writes placeholder grenade and punch sounds as wav files using only the standard library."""
import math, random, struct, sys, wave

RATE = 44100
random.seed(7)

def write(path, samples):
    peak = max(1e-9, max(abs(x) for x in samples))
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x / peak * 0.85)) * 32767)) for x in samples))

def whoosh(seconds):
    n = int(RATE * seconds); out = []; low = 0.0
    for i in range(n):
        t = i / n
        cutoff = 0.05 + 0.25 * math.sin(t * math.pi)
        low += cutoff * (random.uniform(-1, 1) - low)
        out.append(low * math.sin(t * math.pi) ** 1.5)
    return out

def boom(seconds):
    n = int(RATE * seconds); out = []; low = 0.0; phase = 0.0
    for i in range(n):
        t = i / n
        freq = 140 * (1 - t) ** 2 + 35
        phase += 2 * math.pi * freq / RATE
        low += 0.12 * (random.uniform(-1, 1) - low)
        out.append((math.sin(phase) * 0.8 + low * 0.9) * math.exp(-5.0 * t))
    return out

def thump(seconds):
    n = int(RATE * seconds); out = []; phase = 0.0
    for i in range(n):
        t = i / n
        freq = 180 * (1 - t) + 60
        phase += 2 * math.pi * freq / RATE
        click = random.uniform(-1, 1) * math.exp(-60 * t)
        out.append((math.sin(phase) + click * 0.5) * math.exp(-9.0 * t))
    return out

write(sys.argv[1] + "/sfx_grenade_throw.wav", whoosh(0.45))
write(sys.argv[1] + "/sfx_grenade_boom.wav", boom(0.7))
write(sys.argv[1] + "/sfx_punch.wav", thump(0.22))
