#!/usr/bin/env python3
"""
Synthesize Hopr's signature UI sounds from scratch (no third-party assets).

Hopr has its own little sonic identity: a warm, woodblock/marimba-ish timbre
(the "brand"), shaped into two gestures that echo the name — *hopping*:

  click7.m4a  -> "enter mode" : two quick rising notes, a hop *up* (inviting)
  click1.m4a  -> "activate"   : one warm pock that pitches *down*, a landing

Pure stdlib (math + wave) so it runs anywhere without numpy.
"""
import math
import os
import struct
import wave

SR = 44100  # sample rate

# Hopr's shared timbre: a fundamental plus a soft octave, a quiet fifth-ish
# overtone, and one slightly detuned partial for warmth (avoids a sterile sine).
TIMBRE = [(1.00, 1.00), (2.00, 0.34), (3.00, 0.11), (2.01, 0.10)]


def _note(freq, dur, tau, glide=0.0, onset_noise=0.12, attack=0.0015):
    """One note in Hopr's timbre with an exponential decay and smooth attack."""
    n = int(SR * dur)
    out = [0.0] * n
    seed = 0x2545F4914F6CDD1D ^ int(freq)
    for i in range(n):
        t = i / SR
        env = math.exp(-t / tau)
        if t < attack:  # raised-cosine fade-in kills the harsh leading edge
            env *= 0.5 - 0.5 * math.cos(math.pi * t / attack)

        pitch = 1.0 - glide * (t / dur)  # gentle pitch glide = "hop" character
        s = 0.0
        for mult, amp in TIMBRE:
            s += amp * math.sin(2.0 * math.pi * freq * mult * pitch * t)

        if onset_noise > 0.0:  # tiny 2 ms noise transient -> a touch of "click"
            seed = (seed * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
            rnd = (seed >> 33) / float(1 << 31) - 1.0
            s += onset_noise * rnd * math.exp(-t / 0.002)

        out[i] = s * env
    return out


def _mix(total_dur, events):
    """Lay notes onto one buffer at given start times: events = [(start_s, samples)]."""
    n = int(SR * total_dur)
    out = [0.0] * n
    for start, samples in events:
        off = int(SR * start)
        for i, s in enumerate(samples):
            j = off + i
            if 0 <= j < n:
                out[j] += s
    # Final 4 ms linear fade so we land exactly on zero (no end-pop).
    fade = int(SR * 0.004)
    for k in range(fade):
        out[n - 1 - k] *= k / fade
    return out


def _write_wav(path, samples):
    """Normalize to ~ -1.5 dB headroom and write 16-bit mono WAV."""
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = 0.84 / peak
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            frames += struct.pack("<h", int(max(-1.0, min(1.0, s * gain)) * 32767))
        w.writeframes(bytes(frames))


# Musical pitches (Hz), C-pentatonic-ish so the gestures sound friendly.
E6, A6, B6 = 1318.51, 1760.00, 1975.53
A5, E5 = 880.00, 659.26


def main():
    out_dir = os.environ.get("OUT_DIR", "/tmp")

    # ENTER MODE: a hop *up* — E6 then B6 (a perfect fifth), light and inviting.
    enter = _mix(0.150, [
        (0.000, _note(E6, 0.075, tau=0.013, glide=0.04, onset_noise=0.14)),
        (0.052, _note(B6, 0.095, tau=0.016, glide=0.03, onset_noise=0.10)),
    ])
    _write_wav(os.path.join(out_dir, "click7.wav"), enter)

    # ACTIVATE: a warm landing — A5 pitching down, fuller body, satisfying.
    activate = _mix(0.130, [
        (0.000, _note(A5, 0.125, tau=0.020, glide=0.16, onset_noise=0.16)),
    ])
    _write_wav(os.path.join(out_dir, "click1.wav"), activate)

    print(f"wrote click1.wav, click7.wav to {out_dir}")


if __name__ == "__main__":
    main()
