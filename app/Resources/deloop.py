"""砍掉 Whisper 在長音訊上產生的重覆段落。

只認一種證據：同一段文字逐字出現兩次，重覆的那個單位至少 MIN_SPAN 個字，而且兩份
複本之間最多隔 MAX_GAP 個字。跳針重新開始時中間常夾一個「現在」「這個問題」之類的
連接詞，所以不要求兩份複本緊貼在一起。

門檻看的是「重覆的單位有多長」，不是「連續相同的總長度有多長」。「哈」×17 與
「不要」×9 的連續相同總長度都超過 16 個字，但重覆的單位只有一到兩個字，那是正常的
口語強調，不是跳針。

長度一律用「詞」算，不用字元算：中文一個字算一個詞，連在一起的英數算一個詞。英文一個
詞平均五六個字元，所以 database connection pool 只有三個詞卻有 25 個字元，而 24 個
中文字是一整句話。用字元當單位會砍掉夾了英文術語的正常句子。

門檻訂在 24 是量出來的，不是推理出來的：目前收集到的真實跳針，重覆單位最短 26 個詞；
對抗性審查找到的合理重覆最長 21 個詞（把同一句話原封不動再引述一次）。兩邊各留三個詞。

要注意這個門檻在原理上並不安全：真人把超過 24 個詞的句子逐字重講一次，還是會被砍掉。
寧可漏掉也不要砍到正常的句子，所以漏掉的那一邊不再補強。engine.log 每個 chunk 都記了
辨識字數與砍掉後的字數，真的漏掉或砍錯時用那些數字重新調門檻。
"""
import re

MIN_SPAN = 24  # 重覆單位至少這麼多詞才敢砍
MAX_GAP = 8    # 兩份複本之間容許的連接詞長度，這個用字元算，比較嚴

_WORD = re.compile(r"[A-Za-z0-9]+|[^A-Za-z0-9\s]")


def _words(s):
    """數詞：中文一個字一個詞，連在一起的英數算一個詞，空白不算。"""
    return len(_WORD.findall(s))


def _longest_repeat(text):
    """找出夠長也夠近的最長重覆段落，回傳 (起點, 位移, 長度)，找不到回 None。

    位移 d 是兩份複本起點的距離。固定 d 時，text[x] == text[x + d] 的最長連續區段
    就是這個位移下重覆的那一段，而 d 減掉它的長度就是兩份複本之間隔了幾個字。
    這個差可以是負的，代表兩份複本重疊，也就是同一段連著跳針三次以上。

    重覆的單位是 min(d, 連續長度)：連續長度超過 d 時，重覆的單位就是那一個週期。
    一個單位至少佔一個字元，所以先用字元數擋掉絕大多數位置，再去數詞。
    """
    best = None
    for d in range(1, len(text)):
        base, shifted = text[:-d], text[d:]
        run = 0
        for x in range(len(base)):
            run = run + 1 if base[x] == shifted[x] else 0
            if min(d, run) < MIN_SPAN or d - run > MAX_GAP:
                continue
            if best is not None and run <= best[2]:
                continue
            start = x - run + 1
            if _words(text[start:start + min(d, run)]) >= MIN_SPAN:
                best = (start, d, run)
    return best


def _tail_is_debris(tail, unit):
    """判斷重覆段落後面剩下的尾巴是不是跳針的碎屑。

    跳針停下來之前常再吐幾次重覆單位的開頭（「現在現在現在」裡的「現在」）。
    整條尾巴都能用 unit 的開頭拼完、而且拼出兩片以上才算碎屑；只拼出一片有可能是
    使用者接著講的話，留著。
    """
    pieces, rest = 0, tail
    while rest:
        n = 0
        for a, b in zip(rest, unit):
            if a != b:
                break
            n += 1
        if n == 0:
            return False
        pieces, rest = pieces + 1, rest[n:]
    return pieces > 1


def deloop(text):
    """砍掉重覆的段落，砍到文字不再變動為止。每一輪至少砍掉 MIN_SPAN 個字，一定會停。"""
    while True:
        found = _longest_repeat(text)
        if not found:
            return text
        start, shift, length = found
        unit = text[start:start + shift]
        # 整個區段以 shift 為週期。重覆超過一整輪時整個週期都被確認過；只重覆一段
        # （length < shift）時，週期尾端那個連接詞是跳針的開頭，不算使用者講的話。
        keep = start + min(shift, length)
        tail = text[start + shift + length:]
        text = text[:keep] + ("" if _tail_is_debris(tail, unit) else tail)
