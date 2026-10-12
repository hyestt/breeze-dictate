"""語音辨識引擎：從 stdin 讀 JSON 行，辨識 WAV，回 JSON 行。

請求  {"id": 1, "wav": "/path/a.wav"}
回應  {"id": 1, "text": "...", "seconds": 0.12} 或 {"id": 1, "error": "..."}
啟動完成會先印 {"ready": true}。
"""
import argparse, json, os, re, sys, time

import numpy as np
import soundfile as sf
from opencc import OpenCC

ap = argparse.ArgumentParser()
ap.add_argument("--model", required=True)
ap.add_argument("--vocab", required=True)
args = ap.parse_args()

sys.path.insert(0, args.model)
from mlx_whisper_mixed import load_model, transcribe_short_with_model

SR = 16000
cc = OpenCC("s2twp")
model = load_model(args.model)
transcribe_short_with_model(model, np.zeros(SR, dtype=np.float32), context_seconds=10)

_rules, _mtime = [], None


def rules():
    global _rules, _mtime
    try:
        m = os.path.getmtime(args.vocab)
    except OSError:
        return []
    if m != _mtime:
        _mtime = m
        _rules = []
        try:
            entries = json.load(open(args.vocab, encoding="utf-8"))
        except (OSError, ValueError):
            entries = []
        for e in entries:
            for v in e.get("variants", []):
                if not v.strip():
                    continue
                pat = r"\b%s\b" % re.escape(v) if v.isascii() else re.escape(v)
                _rules.append((re.compile(pat, re.I), e["target"]))
        _rules.sort(key=lambda r: -len(r[0].pattern))
    return _rules


def fix_terms(text):
    for rx, target in rules():
        text = rx.sub(lambda _: target, text)
    return text


def cut_restart(text, n=8):
    head = text[:n]
    if len(text) > 2 * n:
        i = text.find(head, n)
        if i > 0:
            return text[:i].rstrip()
    return text


def transcribe(audio):
    parts, step = [], 28 * SR
    for i in range(0, len(audio), step):
        chunk = audio[i:i + step]
        dur = len(chunk) / SR
        ctx = next(c for c in (10, 15, 20, 30) if dur <= c)
        r = transcribe_short_with_model(model, chunk, context_seconds=ctx,
                                        sample_len=min(224, int(dur * 8) + 16))
        parts.append(cut_restart(r["text"].strip()))
    return fix_terms(cc.convert("".join(parts)))


def reply(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


reply({"ready": True})
for line in sys.stdin:
    try:
        req = json.loads(line)
    except ValueError:
        continue
    try:
        audio, rate = sf.read(req["wav"], dtype="float32")
        if audio.ndim == 2:
            audio = audio.mean(axis=1)
        if rate != SR:
            raise ValueError(f"取樣率必須是 {SR}，收到 {rate}")
        t0 = time.time()
        text = transcribe(audio) if len(audio) >= SR * 0.3 else ""
        reply({"id": req["id"], "text": text, "seconds": round(time.time() - t0, 3)})
    except Exception as e:
        reply({"id": req.get("id"), "error": str(e)})
