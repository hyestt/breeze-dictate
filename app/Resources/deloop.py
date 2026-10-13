"""砍掉 Whisper 在長音訊上產生的重覆段落。

只認一種證據：同一段文字逐字出現兩次，重覆的那個單位至少 MIN_SPAN 個詞，而且兩份
複本之間最多隔 MAX_GAP 個字元。跳針重新開始時中間常夾一個「現在」「這個問題」之類的
連接詞，所以不要求兩份複本緊貼在一起。

門檻看的是「重覆的單位有多長」，不是「連續相同的總長度有多長」。「哈」×17 與
「不要」×9 連續相同的總長度很長，但重覆的單位只有一到兩個詞，那是正常的口語強調，
不是跳針。

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

_WORD = re.compile(r"[A-Za-z0-9_]+|\w")


def _words(s):
    """數詞：中文一個字一個詞，連在一起的英數算一個詞，標點與空白都不算。

    標點不算很重要。把點和底線各算一個詞的話，1.2.3 會算成五個詞、
    config_file_path 會算成五個詞，正常句子的引述就會被撐過門檻。
    """
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
    """砍掉重覆的段落，砍到文字不再變動為止。每一輪至少砍掉 MIN_SPAN 個字元，一定會停。"""
    while True:
        found = _longest_repeat(text)
        if not found:
            return text
        start, shift, length = found
        unit = text[start:start + shift]
        # 留到第一份複本結束，再砍掉剛好 shift 個字元。被砍掉的那一段裡，位置在
        # start + shift 之後的每一個字元都逐字等於它前面 shift 個字元，是確定的複本；
        # 只重覆一段（length < shift）時，前面多出來的那幾個字是連接詞。
        #
        # 不可以只留一個週期。連續相同的長度超過一個週期時，多出來的那幾個字也可能是
        # 下一句的開頭（跳針單位開頭是「然後」，使用者下一句也從「然後」開始），
        # 分不出來，所以留著。寧可留下半截，也不要吃掉使用者講的字。
        tail = text[start + shift + length:]
        debris = _tail_is_debris(tail, unit)
        # 但 chunk 以碎屑收尾時，代表跳針一路吐到結尾，後面沒有真的話了，那幾個延伸字
        # 也是跳針吐出來的，這時只留一個週期。
        keep = start + (shift if debris and tail else length)
        text = text[:keep] + ("" if debris else tail)
