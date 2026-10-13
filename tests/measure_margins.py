#!/usr/bin/env python3
"""量 MIN_SPAN 與 RATIO 在現有語料上的餘裕。deloop.py 註解寫的數字從這裡來。

語料就是 test_deloop.py 的三個清單。LOOPED 與 EXACT 是必須砍的，CLEAN 是不可以砍的。
每一筆都去枚舉所有「位移 d、串起來的相同區段」的窗格，對每個窗格取兩個數字：
重覆單位有幾個詞，以及窗格裡有多少比例的字元逐字相同。然後各取兩側最糟的那一筆：

  必須砍的  單位詞數取最長的那個窗格（偵測器只需要找到一個），這個數字要 >= MIN_SPAN。
            近似度取「單位已達 MIN_SPAN 的窗格」裡最高的，那是砍到它最低需要的近似度，
            這個數字要 >= RATIO。
  不可以砍的 單位詞數取「近似度已達 RATIO 的窗格」裡最長的，這個數字要 < MIN_SPAN。
            近似度取「單位已達 MIN_SPAN 的窗格」裡最高的，這個數字要 < RATIO。

門檻改過、或是語料加了新句子就重跑一次。四個餘裕都要是正的，不然這個檔案會回非零。
真的漏砍或砍錯時，把那一句加進 test_deloop.py 再跑一次，就知道門檻還能不能動。
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app" / "Resources"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from deloop import MAX_GAP, MIN_SPAN, RATIO, _same_runs, _words
from test_deloop import CLEAN, EXACT, LOOPED


def _windows(text):
    """枚舉所有夠近的窗格，每個回傳 (單位詞數, 字元相同比例)。"""
    for d in range(1, len(text)):
        runs = _same_runs(text, d)
        for i, (start, _) in enumerate(runs):
            same = 0
            for begin, length in runs[i:]:
                same += length
                total = begin + length - start
                if d - total > MAX_GAP:
                    continue
                yield _words(text[start:start + min(d, total)]), same / total


def _peak(text, *, min_ratio=0.0, min_span=0):
    """符合條件的窗格裡，單位最長的詞數與相同比例最高的值，都沒有就回 (0, 0.0)。"""
    spans = [w for w, r in _windows(text) if r >= min_ratio]
    ratios = [r for w, r in _windows(text) if w >= min_span]
    return max(spans, default=0), max(ratios, default=0.0)


def main():
    must_cut = [t for t, _ in LOOPED] + [t for t, _ in EXACT]
    keep = list(CLEAN)

    cut_span = min(_peak(t)[0] for t in must_cut)
    cut_ratio = min(_peak(t, min_span=MIN_SPAN)[1] for t in must_cut)
    keep_span = max(_peak(t, min_ratio=RATIO)[0] for t in keep)
    keep_ratio = max(_peak(t, min_span=MIN_SPAN)[1] for t in keep)

    print(f"語料：必須砍 {len(must_cut)} 筆，不可以砍 {len(keep)} 筆")
    print(f"MIN_SPAN = {MIN_SPAN} 詞")
    print(f"  必須砍的最短單位 {cut_span} 詞，餘裕 {cut_span - MIN_SPAN} 詞")
    print(f"  不可以砍的最長單位 {keep_span} 詞，餘裕 {MIN_SPAN - keep_span} 詞")
    print(f"RATIO = {RATIO}")
    print(f"  必須砍的最低近似度 {cut_ratio:.3f}，餘裕 {cut_ratio - RATIO:+.3f}")
    print(f"  不可以砍的最高近似度 {keep_ratio:.3f}，餘裕 {RATIO - keep_ratio:+.3f}")

    bad = []
    if cut_span < MIN_SPAN:
        # 單位已經不夠長時，那一筆根本沒有達 MIN_SPAN 的窗格，近似度會是 0，不另外報。
        bad.append(f"MIN_SPAN {MIN_SPAN} 太大，有跳針的單位只有 {cut_span} 詞")
    elif cut_ratio < RATIO:
        bad.append(f"RATIO {RATIO} 太高，有跳針只有 {cut_ratio:.3f} 相同")
    if keep_span >= MIN_SPAN:
        bad.append(f"MIN_SPAN {MIN_SPAN} 太小，有正常句子的單位到了 {keep_span} 詞")
    if keep_ratio >= RATIO:
        bad.append(f"RATIO {RATIO} 太低，有正常句子到了 {keep_ratio:.3f} 相同")
    for line in bad:
        print("FAIL", line)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
