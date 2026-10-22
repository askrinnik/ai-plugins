"""Transcribe an audio file with faster-whisper (local, no cloud).

Usage:
    <whisper dir>\\.venv\\Scripts\\python.exe scripts\\transcribe.py <audio> <out_prefix>
        [--model large-v3] [--language en] [--device cuda|cpu]
        [--languages en,ru [--switch 00:12:30[,00:40:00]] [--window 30]]

Writes <out_prefix>.txt ("[hh:mm:ss] text" per segment) and <out_prefix>.json (segments with
start/end/text/avg_logprob). Speakers are not labelled; that is done afterwards by reading the text.

Several languages in one call (--languages en,ru): the script runs one pass per language over the whole audio,
then keeps from each pass only the segments that start in time spans of that language, and merges them by time.
The language of each time span comes from:
  --switch hh:mm:ss[,hh:mm:ss...]  times when the language changes; the spans take the languages of --languages in
                                   turn (en until the first switch, ru until the second, en again, ...);
  otherwise                        language detection on windows of --window seconds (default 30), limited to the
                                   given languages and smoothed so that a single odd window takes its neighbours'
                                   language.
In this mode each JSON segment also has "language", and <out_prefix>.languages.txt lists the language spans. Check
the spans: detection can be wrong near a switch or in a window with little speech; then rerun with --switch.

The virtual environment and the models live in the whisper dir: JOBSEARCH_WHISPER, else
%LOCALAPPDATA%\\ai-plugins\\jobsearch-kit\\whisper. They stay outside the plugin and the workspace, so that a plugin
update does not remove them and a synced folder does not copy them. Setup: scripts\\install-whisper.ps1.
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

WHISPER_DIR = Path(os.environ.get("JOBSEARCH_WHISPER")
                   or Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
                   / "ai-plugins" / "jobsearch-kit" / "whisper")
SAMPLE_RATE = 16000


def add_cuda_dll_dirs():
    # cuBLAS and cuDNN come from the nvidia-* pip packages; CTranslate2 needs their DLLs on the search path.
    nvidia = Path(sys.prefix) / "Lib" / "site-packages" / "nvidia"
    if not nvidia.is_dir():
        return
    for bin_dir in nvidia.glob("*/bin"):
        os.add_dll_directory(str(bin_dir))
        os.environ["PATH"] = str(bin_dir) + os.pathsep + os.environ["PATH"]


def fmt(seconds):
    s = int(seconds)
    return f"{s // 3600:02d}:{s % 3600 // 60:02d}:{s % 60:02d}"


def parse_time(text):
    parts = [float(p) for p in text.strip().split(":")]
    seconds = 0.0
    for p in parts:
        seconds = seconds * 60 + p
    return seconds


def transcribe(model, audio, language):
    segments, info = model.transcribe(audio, language=language, beam_size=5,
                                      vad_filter=True, condition_on_previous_text=False)
    return segments, info


def to_record(seg):
    return {"start": round(seg.start, 2), "end": round(seg.end, 2), "text": seg.text.strip(),
            "avg_logprob": round(seg.avg_logprob, 3)}


def single_language(model, args):
    started = time.time()
    segments, info = transcribe(model, args.audio, args.language)
    print(f"Audio duration: {fmt(info.duration)}", flush=True)

    out_txt = Path(args.out_prefix + ".txt")
    out_json = Path(args.out_prefix + ".json")
    out_txt.parent.mkdir(parents=True, exist_ok=True)
    result = []
    with out_txt.open("w", encoding="utf-8") as txt:
        for seg in segments:
            rec = to_record(seg)
            result.append(rec)
            txt.write(f"[{fmt(seg.start)}] {rec['text']}\n")
            txt.flush()
            print(f"[{fmt(seg.start)}] {rec['text']}", flush=True)
    out_json.write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"Done: {len(result)} segments in {time.time() - started:.0f} s", flush=True)


def spans_from_switches(switches, languages, duration):
    """Language spans from switch times: the languages take turns in the given order."""
    bounds = [0.0] + sorted(parse_time(s) for s in switches) + [duration]
    return [(bounds[i], bounds[i + 1], languages[i % len(languages)]) for i in range(len(bounds) - 1)]


def spans_from_detection(model, audio, languages, window):
    """Language spans from detection on fixed windows, limited to the given languages and smoothed."""
    step = int(window * SAMPLE_RATE)
    labels = []
    for start in range(0, len(audio), step):
        chunk = audio[start:start + step]
        lang = None
        if len(chunk) >= SAMPLE_RATE:  # skip a tail shorter than 1 s
            try:
                _, _, probs = model.detect_language(audio=chunk, vad_filter=True)
                scores = {code: p for code, p in probs if code in languages}
                if scores:
                    lang = max(scores, key=scores.get)
            except Exception:  # no speech in the window
                lang = None
        labels.append(lang)
        print(f"  detect [{fmt(start / SAMPLE_RATE)}] {lang or '-'}", flush=True)

    # Windows without speech take the previous language (or the next one at the start).
    for i in range(len(labels)):
        if labels[i] is None:
            labels[i] = labels[i - 1] if i else None
    for i in range(len(labels) - 1, -1, -1):
        if labels[i] is None:
            labels[i] = labels[i + 1] if i + 1 < len(labels) and labels[i + 1] else languages[0]
    # A single window between two windows of another language takes their language.
    for i in range(1, len(labels) - 1):
        if labels[i - 1] == labels[i + 1] != labels[i]:
            labels[i] = labels[i - 1]

    spans = []
    for i, lang in enumerate(labels):
        start, end = i * window, (i + 1) * window
        if spans and spans[-1][2] == lang:
            spans[-1] = (spans[-1][0], end, lang)
        else:
            spans.append((start, end, lang))
    duration = len(audio) / SAMPLE_RATE
    spans[-1] = (spans[-1][0], duration, spans[-1][2])
    return spans


def language_at(spans, t):
    for start, end, lang in spans:
        if start <= t < end:
            return lang
    return spans[-1][2]


def several_languages(model, args):
    from faster_whisper import decode_audio

    started = time.time()
    languages = [code.strip() for code in args.languages.split(",") if code.strip()]
    audio = decode_audio(args.audio, sampling_rate=SAMPLE_RATE)
    duration = len(audio) / SAMPLE_RATE
    print(f"Audio duration: {fmt(duration)}; languages: {', '.join(languages)}", flush=True)

    if args.switch:
        spans = spans_from_switches(args.switch.split(","), languages, duration)
    else:
        print(f"Detecting the language in {args.window}-second windows", flush=True)
        spans = spans_from_detection(model, audio, languages, args.window)
    span_lines = [f"{fmt(s)}-{fmt(e)} {lang}" for s, e, lang in spans]
    print("Language spans:\n  " + "\n  ".join(span_lines), flush=True)

    result = []
    for lang in languages:
        if not any(l == lang for _, _, l in spans):
            continue
        print(f"Pass: {lang}", flush=True)
        segments, _ = transcribe(model, audio, lang)
        for seg in segments:
            # A segment belongs to the language of its start, so a phrase that crosses a switch is kept once.
            if language_at(spans, seg.start) == lang:
                rec = to_record(seg)
                rec["language"] = lang
                result.append(rec)
                print(f"[{fmt(seg.start)}] ({lang}) {rec['text']}", flush=True)
    result.sort(key=lambda r: r["start"])

    out = Path(args.out_prefix)
    out.parent.mkdir(parents=True, exist_ok=True)
    Path(args.out_prefix + ".txt").write_text(
        "".join(f"[{fmt(r['start'])}] {r['text']}\n" for r in result), encoding="utf-8")
    Path(args.out_prefix + ".json").write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")
    Path(args.out_prefix + ".languages.txt").write_text("\n".join(span_lines) + "\n", encoding="utf-8")
    print(f"Done: {len(result)} segments in {time.time() - started:.0f} s", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("audio")
    parser.add_argument("out_prefix")
    parser.add_argument("--model", default="large-v3")
    parser.add_argument("--language", default="en")
    parser.add_argument("--languages", help="several languages, for example en,ru")
    parser.add_argument("--switch", help="language switch times, for example 00:12:30 or 00:12:30,00:40:00")
    parser.add_argument("--window", type=int, default=30, help="detection window in seconds")
    parser.add_argument("--device", default="cuda")
    args = parser.parse_args()
    if args.switch and not args.languages:
        parser.error("--switch needs --languages")

    # Print UTF-8 even when stdout is redirected to a file under a non-UTF-8 Windows code page.
    sys.stdout.reconfigure(encoding="utf-8")
    add_cuda_dll_dirs()
    from faster_whisper import WhisperModel

    compute_type = "float16" if args.device == "cuda" else "int8"
    model = WhisperModel(args.model, device=args.device, compute_type=compute_type,
                         download_root=str(WHISPER_DIR / "models"))

    if args.languages and len(args.languages.split(",")) > 1:
        several_languages(model, args)
    else:
        if args.languages:
            args.language = args.languages.strip()
        single_language(model, args)


if __name__ == "__main__":
    main()
