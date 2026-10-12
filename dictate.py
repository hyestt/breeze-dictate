"""按住右 Option 說話，放開後轉成繁體中文並貼到游標處。"""
import json, re, subprocess, sys, threading, time
import numpy as np
import sounddevice as sd
from opencc import OpenCC
from pynput import keyboard

sys.path.insert(0, "model")
from mlx_whisper_mixed import load_model, transcribe_short_with_model

HOTKEY = keyboard.Key.alt_r
SR = 16000
cc = OpenCC("s2twp")  # 簡體→台灣繁體（含台灣用語）
def load_rules():
    data = json.load(open("replacements.json", encoding="utf-8"))
    rules = []
    for target, variants in data.items():
        for v in variants:
            pat = r"\b%s\b" % re.escape(v) if v.isascii() else re.escape(v)
            rules.append((re.compile(pat, re.I), target))
    rules.sort(key=lambda r: -len(r[0].pattern))  # 長詞優先（cloud code 先於 cloud）
    return rules


RULES = load_rules()


def fix_terms(text):
    for rx, target in RULES:
        text = rx.sub(target, text)
    return text


model = load_model("model")
transcribe_short_with_model(model, np.zeros(SR, dtype=np.float32), context_seconds=10)  # 預熱

frames, stream, recording = [], None, False


def on_audio(indata, n, t, status):
    frames.append(indata[:, 0].copy())


def cut_restart(text, n=8):
    """模型講完後常把開頭重念一遍；偵測到開頭片段再次出現就截掉。"""
    head = text[:n]
    if len(text) > 2 * n:
        i = text.find(head, n)
        if i > 0:
            return text[:i].rstrip()
    return text


def transcribe(audio):
    parts = []
    step = 28 * SR
    for i in range(0, len(audio), step):
        chunk = audio[i:i + step]
        dur = len(chunk) / SR
        ctx = next(c for c in (10, 15, 20, 30) if dur <= c)  # 靜音留白越少越不亂續寫
        r = transcribe_short_with_model(model, chunk, context_seconds=ctx,
                                        sample_len=min(224, int(dur * 8) + 16))
        parts.append(cut_restart(r["text"].strip()))
    return fix_terms(cc.convert("".join(parts)))


def paste(text):
    old = subprocess.run(["pbpaste"], capture_output=True).stdout
    subprocess.run(["pbcopy"], input=text.encode())
    kb = keyboard.Controller()
    with kb.pressed(keyboard.Key.cmd):
        kb.tap("v")
    time.sleep(0.3)
    subprocess.run(["pbcopy"], input=old)


def finish():
    audio = np.concatenate(frames) if frames else np.zeros(0, dtype=np.float32)
    if len(audio) < SR * 0.3:
        return
    t0 = time.time()
    text = transcribe(audio)
    print(f"[{time.time()-t0:.2f}s] {text}", flush=True)
    if text:
        paste(text)


def on_press(key):
    global stream, recording
    if key == HOTKEY and not recording:
        recording = True
        frames.clear()
        stream = sd.InputStream(samplerate=SR, channels=1, dtype="float32", callback=on_audio)
        stream.start()
        subprocess.Popen(["afplay", "/System/Library/Sounds/Tink.aiff"])


def on_release(key):
    global stream, recording
    if key == HOTKEY and recording:
        recording = False
        stream.stop(); stream.close()
        threading.Thread(target=finish, daemon=True).start()


print("就緒：按住右 Option 說話，放開後貼上。", flush=True)
with keyboard.Listener(on_press=on_press, on_release=on_release) as l:
    l.join()
