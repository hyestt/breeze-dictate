"""語音辨識引擎：從 stdin 讀 JSON 行，辨識 WAV，回 JSON 行。

請求  {"id": 1, "wav": "/path/a.wav"}
回應  {"id": 1, "text": "...", "seconds": 0.12} 或 {"id": 1, "error": "..."}
啟動完成會先印 {"ready": true}。
--settings 指向 settings.json 時，punctuation 為 true 且同資料夾有 punct-model 就在辨識後補標點。
"""
import argparse, json, os, re, sys, time

import numpy as np
import soundfile as sf
from opencc import OpenCC

ap = argparse.ArgumentParser()
ap.add_argument("--model", required=True)
ap.add_argument("--vocab", required=True)
ap.add_argument("--settings")
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


PUNCT_MIN_CHARS = 4
PUNCT_SYS = ("你是中文標點修復器。使用者給你一段語音辨識出來的文字，裡面可能夾雜英文。"
             "你只能加上標點符號（，。？！、：；），不可以增加、刪除或修改任何一個字，"
             "也不可以翻譯英文。直接輸出修好的那一段，不要加任何說明。")
PUNCT_CHARS = "，。？！、：；「」（）,.?!;:\"'()… \n"
cc_tw = OpenCC("s2tw")
_settings_mtime, _punct_wanted = None, False
_punct = None          # (model, tokenizer, generate, sampler) 載入成功後保留
_punct_failed = False  # 載入失敗後不重試，直到設定檔再改動


def punct_dir():
    return os.path.join(os.path.dirname(os.path.abspath(args.settings)), "punct-model")


def punct_wanted():
    global _settings_mtime, _punct_wanted, _punct_failed
    if not args.settings:
        return False
    try:
        m = os.path.getmtime(args.settings)
    except OSError:
        return False
    if m != _settings_mtime:
        _settings_mtime = m
        _punct_failed = False
        try:
            _punct_wanted = json.load(open(args.settings, encoding="utf-8")).get("punctuation") is True
        except (OSError, ValueError, AttributeError):
            _punct_wanted = False
    return _punct_wanted


def punctuator():
    """只在設定開啟且模型資料夾存在時載入；失敗回 None，辨識照常。"""
    global _punct, _punct_failed
    if _punct or _punct_failed or not punct_wanted() or not os.path.isdir(punct_dir()):
        return _punct
    try:
        from mlx_lm import load, generate
        from mlx_lm.sample_utils import make_sampler
        m, tok = load(punct_dir())
        _punct = (m, tok, generate, make_sampler(temp=0.0))
        add_punctuation("測試一下標點")
    except Exception as e:
        _punct, _punct_failed = None, True
        print(f"標點模型載入失敗：{e}", file=sys.stderr, flush=True)
    return _punct


def _bare(s):
    return re.sub("[%s]" % re.escape(PUNCT_CHARS), "", cc_tw.convert(s)).lower()


def add_punctuation(text):
    m, tok, generate, sampler = _punct
    msgs = [{"role": "system", "content": PUNCT_SYS}, {"role": "user", "content": text}]
    p = tok.apply_chat_template(msgs, add_generation_prompt=True, enable_thinking=False)
    out = generate(m, tok, prompt=p, max_tokens=len(text) + 60, verbose=False,
                   sampler=sampler).split("</think>")[-1].strip()
    out = cc_tw.convert(out)
    # 守門：任何一個字被改動就退回原文。
    return out if _bare(out) == _bare(text) else text


def punctuate(text):
    if len(text.strip()) < PUNCT_MIN_CHARS or not punctuator():
        return text
    try:
        return add_punctuation(text)
    except Exception as e:
        print(f"補標點失敗：{e}", file=sys.stderr, flush=True)
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


punctuator()
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
        text = punctuate(transcribe(audio)) if len(audio) >= SR * 0.3 else ""
        reply({"id": req["id"], "text": text, "seconds": round(time.time() - t0, 3)})
    except Exception as e:
        reply({"id": req.get("id"), "error": str(e)})
