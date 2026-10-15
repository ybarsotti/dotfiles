import asyncio
import base64
import json
import os
import subprocess
import sys
import unicodedata
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AUDIO = ROOT / "public" / "audio"
MANIFEST = ROOT / "src" / "manifest.json"
NARRATION = ROOT / "narration.json"
PROVIDERS = ("edge", "eleven")


def seconds(path: Path) -> float:
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        check=True, capture_output=True, text=True,
    )
    return float(probe.stdout.strip())


def plain(text: str) -> str:
    stripped = "".join(char for char in unicodedata.normalize("NFD", text.lower()) if unicodedata.category(char) != "Mn")
    return "".join(char for char in stripped if char.isalnum())


def align(text: str, spoken: list[dict]) -> list[dict]:
    stream, owners = "", []
    for index, piece in enumerate(spoken):
        chars = plain(piece["text"])
        stream += chars
        owners += [(index, offset, len(chars)) for offset in range(len(chars))]

    def moment(position: int, edge: int) -> float:
        index, offset, length = owners[position]
        piece = spoken[index]
        return piece["start"] + (piece["end"] - piece["start"]) * (offset + edge) / length

    words, cursor = [], 0
    for token in text.split():
        target = plain(token)
        found = -1
        if target:
            found = cursor if stream.startswith(target, cursor) else stream.find(target, cursor, cursor + len(target) + 24)
        if found < 0:
            words.append({"text": token, "start": None, "end": None})
            continue
        words.append({"text": token, "start": moment(found, 0), "end": moment(found + len(target) - 1, 1)})
        cursor = found + len(target)
    for index, word in enumerate(words):
        if word["start"] is None:
            before = next((w["end"] for w in reversed(words[:index]) if w["end"] is not None), 0.0)
            after = next((w["start"] for w in words[index + 1:] if w["start"] is not None), before + 0.2)
            word["start"], word["end"] = before, after
    return words


def words_from_characters(alignment: dict) -> list[dict]:
    words, current, start, end = [], "", None, 0.0
    for char, begin, finish in zip(
        alignment["characters"],
        alignment["character_start_times_seconds"],
        alignment["character_end_times_seconds"],
    ):
        if char.isspace():
            if current:
                words.append({"text": current, "start": start, "end": end})
            current, start = "", None
            continue
        start = begin if start is None else start
        current += char
        end = finish
    if current:
        words.append({"text": current, "start": start, "end": end})
    return words


def merge_spelled(words: list[dict], spelled: dict[str, str]) -> list[dict]:
    merged, index = [], 0
    while index < len(words):
        for spoken, shown in spelled.items():
            parts = spoken.split()
            window = words[index:index + len(parts)]
            if [w["text"].strip(".,:;?!") for w in window] == parts:
                tail = window[-1]["text"][len(parts[-1]):]
                merged.append({"text": shown + tail, "start": window[0]["start"], "end": window[-1]["end"]})
                index += len(parts)
                break
        else:
            merged.append(words[index])
            index += 1
    return merged


def edge(text: str, target: Path, voice: dict) -> list[dict]:
    import edge_tts

    async def run() -> list[dict]:
        spoken = []
        communicate = edge_tts.Communicate(text, voice["edge"], boundary="WordBoundary")
        with target.open("wb") as media:
            async for chunk in communicate.stream():
                if chunk["type"] == "audio":
                    media.write(chunk["data"])
                elif chunk["type"] == "WordBoundary":
                    begin = chunk["offset"] / 1e7
                    spoken.append({"text": chunk["text"], "start": begin, "end": begin + chunk["duration"] / 1e7})
        return spoken

    return align(text, asyncio.run(run()))


def eleven(text: str, target: Path, voice: dict) -> list[dict]:
    settings = voice["eleven"]
    request = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{settings['voice_id']}/with-timestamps?output_format=mp3_44100_128",
        data=json.dumps({
            "text": text,
            "model_id": settings.get("model", "eleven_multilingual_v2"),
            "voice_settings": {"stability": 0.5, "similarity_boost": 0.8, "style": 0.0, "use_speaker_boost": True},
        }).encode(),
        headers={"xi-api-key": os.environ["ELEVENLABS_API_KEY"], "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        body = json.load(response)
    target.write_bytes(base64.b64decode(body["audio_base64"]))
    return words_from_characters(body["alignment"])


def main() -> None:
    provider = sys.argv[1] if len(sys.argv) > 1 else "edge"
    if provider not in PROVIDERS:
        sys.exit(f"usage: tts.py [{'|'.join(PROVIDERS)}] [segment id ...]")
    only = set(sys.argv[2:])
    narration = json.loads(NARRATION.read_text())
    synthesize = {"edge": edge, "eleven": eleven}[provider]
    voice, spelled = narration["voice"][provider], narration.get("spelled", {})
    previous = {}
    if MANIFEST.exists():
        previous = {entry["id"]: entry for entry in json.loads(MANIFEST.read_text())["segments"]}
    AUDIO.mkdir(parents=True, exist_ok=True)
    entries, sent = [], 0
    for segment in narration["segments"]:
        name = segment["id"]
        target = AUDIO / f"{name}.mp3"
        cached = previous.get(name) if target.exists() else None
        # A new voice or spelled map changes the audio or the captions, so it is not a cache hit.
        unchanged = cached and [cached["text"], cached["provider"], cached.get("voice"), cached.get("spelled")] == [
            segment["text"], provider, voice, spelled,
        ]
        skipped = cached and only and name not in only
        if unchanged or skipped:
            words, used = cached["words"], {key: cached.get(key) for key in ("provider", "voice", "spelled")}
        else:
            words = merge_spelled(synthesize(segment["text"], target, narration["voice"]), spelled)
            used = {"provider": provider, "voice": voice, "spelled": spelled}
            sent += len(segment["text"])
        entries.append({**segment, **used, "audio": f"audio/{name}.mp3", "duration": seconds(target), "words": words})
        print(f"{name:28s} {entries[-1]['duration']:6.2f}s {len(words):3d} words {used['provider']}{' (cached)' if unchanged or skipped else ''}")
    MANIFEST.write_text(json.dumps({"coordinateSpace": narration["coordinateSpace"], "segments": entries}, ensure_ascii=False, indent=1))
    print(f"total {sum(entry['duration'] for entry in entries):.1f}s, characters synthesized this run: {sent}")


if __name__ == "__main__":
    main()
