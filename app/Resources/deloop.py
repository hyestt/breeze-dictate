"""砍掉 Whisper 在長音訊上產生的重覆段落。

門檻取高，寧可漏掉也不要砍到正常的句子。
"""
import difflib


def cut_restart(text, n=8):
    head = text[:n]
    if len(text) > 2 * n:
        i = text.find(head, n)
        if i > 0:
            return text[:i].rstrip()
    return text


def collapse_loops(text, min_block=10, ratio=0.9, min_len=60):
    """砍掉尾端重覆的整段。"""
    if len(text) < min_len:
        return text
    for _ in range(3):
        changed = False
        for p in range(len(text) // 2, min_block - 1, -1):
            a, b = text[-2 * p:-p], text[-p:]
            if a == b or difflib.SequenceMatcher(None, a, b, autojunk=False).ratio() >= ratio:
                text, changed = text[:-p], True
                break
        if not changed:
            break
    return text


def drop_partial_tail(text, min_block=6, ratio=0.9, min_len=40):
    """砍完整段重覆後尾端常剩半句，它會和前面某一段的開頭高度相似。

    只處理長文字。短句本來就可能合理地重覆用詞。
    """
    if len(text) < min_len:
        return text
    for n in range(len(text) // 3, min_block - 1, -1):
        tail = text[-n:]
        i = text.find(tail[:min_block], 0, len(text) - n)
        if i >= 0 and difflib.SequenceMatcher(None, text[i:i + n], tail, autojunk=False).ratio() >= ratio:
            return text[:-n].rstrip()
    return text


def deloop(text):
    return drop_partial_tail(collapse_loops(cut_restart(text)))
