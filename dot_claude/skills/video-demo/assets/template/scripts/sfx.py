import struct
import wave
from pathlib import Path

import numpy as np

SR = 48000
OUT = Path(__file__).resolve().parent.parent / "public" / "sfx"
rng = np.random.default_rng(4257)


def write(name: str, samples: np.ndarray, gain: float = 0.9) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    data = np.clip(samples / (np.max(np.abs(samples)) + 1e-9) * gain, -1, 1)
    stereo = np.stack([data, data], axis=1) if data.ndim == 1 else data
    pcm = (stereo * 32767).astype("<i2")
    with wave.open(str(OUT / f"{name}.wav"), "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(pcm.tobytes())
    print(f"{name}.wav {len(data) / SR:.2f}s")


def seconds(duration: float) -> np.ndarray:
    return np.arange(int(duration * SR)) / SR


def bandpass_noise(duration: float, low: float, high: float, sweep: float = 1.0) -> np.ndarray:
    noise = rng.standard_normal(int(duration * SR))
    spectrum = np.fft.rfft(noise)
    freqs = np.fft.rfftfreq(len(noise), 1 / SR)
    band = np.exp(-((np.log(np.maximum(freqs, 1)) - np.log(np.sqrt(low * high))) ** 2) / (2 * (np.log(high / low) / 4) ** 2))
    shaped = np.fft.irfft(spectrum * band, n=len(noise))
    if sweep != 1.0:
        t = seconds(duration)
        phase = np.cumsum(np.linspace(1, sweep, len(t))) / SR
        shaped = shaped * (0.6 + 0.4 * np.sin(2 * np.pi * 4 * phase))
    return shaped


def envelope(duration: float, attack: float, release: float, curve: float = 2.0) -> np.ndarray:
    t = seconds(duration)
    env = np.ones_like(t)
    env[t < attack] = (t[t < attack] / attack) ** curve
    tail = t > duration - release
    env[tail] = ((duration - t[tail]) / release) ** curve
    return env


def tone(duration: float, freq: float, harmonics=(1.0, 0.35, 0.15, 0.08), decay: float = 3.0) -> np.ndarray:
    t = seconds(duration)
    signal = sum(amp * np.sin(2 * np.pi * freq * (index + 1) * t) for index, amp in enumerate(harmonics))
    return signal * np.exp(-decay * t)


def whoosh() -> np.ndarray:
    duration = 0.9
    noise = bandpass_noise(duration, 180, 2600)
    t = seconds(duration)
    env = np.exp(-((t - 0.32) ** 2) / (2 * 0.13**2))
    stereo_left = noise * env * (0.5 + 0.5 * np.cos(np.pi * t / duration))
    stereo_right = noise * env * (0.5 - 0.5 * np.cos(np.pi * t / duration))
    return np.stack([stereo_left, stereo_right], axis=1)


def click() -> np.ndarray:
    duration = 0.07
    noise = bandpass_noise(duration, 900, 5000)
    body = tone(duration, 1900, harmonics=(1.0, 0.2), decay=90)
    return (noise * envelope(duration, 0.002, 0.05, 1.5) * 0.6 + body * 0.8)


def tick() -> np.ndarray:
    duration = 0.045
    noise = bandpass_noise(duration, 1800, 7000)
    return noise * envelope(duration, 0.001, 0.035, 1.3)


def riser() -> np.ndarray:
    duration = 3.2
    t = seconds(duration)
    noise = bandpass_noise(duration, 120, 4000, sweep=6)
    swell = (t / duration) ** 2.4
    pulse = 0.75 + 0.25 * np.sin(2 * np.pi * (2 + 10 * t / duration) * t)
    shimmer = tone(duration, 329.63, harmonics=(0.6, 0.3, 0.2, 0.1, 0.05), decay=0.0) * (t / duration) ** 3 * 0.35
    out = (noise * swell * pulse + shimmer)
    out[-int(0.05 * SR):] *= np.linspace(1, 0, int(0.05 * SR))
    return out


def ding() -> np.ndarray:
    duration = 1.6
    return tone(duration, 1318.5, harmonics=(1.0, 0.25, 0.12, 0.05), decay=2.6) + tone(duration, 659.25, harmonics=(0.5, 0.1), decay=1.8) * 0.5


def swell() -> np.ndarray:
    duration = 1.4
    t = seconds(duration)
    pad = sum(np.sin(2 * np.pi * freq * t) for freq in (164.81, 246.94, 329.63, 493.88))
    env = np.sin(np.pi * t / duration) ** 1.6
    return pad * env


def thud() -> np.ndarray:
    duration = 0.6
    t = seconds(duration)
    body = np.sin(2 * np.pi * (70 * np.exp(-6 * t) + 38) * t) * np.exp(-7 * t)
    noise = bandpass_noise(duration, 60, 500) * np.exp(-22 * t) * 0.5
    return body + noise


def chime() -> np.ndarray:
    duration = 2.2
    notes = [(0.0, 659.25), (0.12, 987.77), (0.24, 1318.5)]
    out = np.zeros(int(duration * SR))
    for start, freq in notes:
        offset = int(start * SR)
        note = tone(duration - start, freq, harmonics=(1.0, 0.2, 0.08), decay=2.2)
        out[offset:offset + len(note)] += note
    return out


write("whoosh", whoosh(), 0.55)
write("click", click(), 0.5)
write("tick", tick(), 0.35)
write("riser", riser(), 0.7)
write("ding", ding(), 0.45)
write("swell", swell(), 0.4)
write("thud", thud(), 0.75)
write("chime", chime(), 0.45)
