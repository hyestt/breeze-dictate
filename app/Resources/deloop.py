"""砍掉 Whisper 在長音訊上產生的重覆段落。

只認一種證據：同一段文字逐字出現兩次，長度至少 MIN_SPAN 個字，而且兩份複本之間
最多隔 MAX_GAP 個字。跳針重新開始時中間常夾一個「現在」「這個問題」之類的連接詞，
所以不要求兩份複本緊貼在一起。

中文口語本來就一直在重覆短詞組（強調、排比、列舉、同一個人名），所以門檻訂在
遠高於口語重覆長度的地方。寧可漏掉也不要砍到正常的句子。
"""

MIN_SPAN = 16  # 口語合理重覆的長度實測到九個字（「我希望這個功能可以」），取將近兩倍當安全邊界
MAX_GAP = 8    # 兩份複本之間容許的連接詞長度


def _longest_repeat(text):
    """找出夠長也夠近的最長重覆段落，回傳 (起點, 位移, 長度)，找不到回 None。

    位移 d 是兩份複本起點的距離。固定 d 時，text[x] == text[x + d] 的最長連續區段
    就是這個位移下重覆的那一段，而 d 減掉它的長度就是兩份複本之間隔了幾個字。
    這個差可以是負的，代表兩份複本重疊，也就是同一段連著跳針三次以上。
    """
    best = None
    for d in range(1, len(text)):
        base, shifted = text[:-d], text[d:]
        run = 0
        for x in range(len(base)):
            run = run + 1 if base[x] == shifted[x] else 0
            if run >= MIN_SPAN and d - run <= MAX_GAP and (best is None or run > best[2]):
                best = (x - run + 1, d, run)
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


def collapse_loops(text):
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


def cut_restart(text):
    """整句從頭重講一次：開頭那段又出現在後面，就從它再次出現的地方切掉。

    這種跳針的兩份複本之間可以隔很遠，collapse_loops 的 MAX_GAP 擋不住，所以單獨處理。
    比對長度同樣用 MIN_SPAN：比這短的開頭，正常句子也會重覆（「我希望這個功能可以」）。
    """
    head = text[:MIN_SPAN]
    if len(text) > 2 * MIN_SPAN:
        i = text.find(head, MIN_SPAN)
        if i > 0:
            return text[:i].rstrip()
    return text


def deloop(text):
    return collapse_loops(cut_restart(text))
