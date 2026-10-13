"""砍掉 Whisper 在長音訊上產生的重覆段落。

只認一種證據：同一段文字幾乎逐字出現兩次。重覆的那個單位至少 MIN_SPAN 個詞，兩份
複本之間最多隔 MAX_GAP 個字元，而且對齊之後至少 RATIO 的字元逐字相同。跳針重新開始時
中間常夾一個「現在」「這個問題」之類的連接詞，所以不要求兩份複本緊貼在一起。

不要求逐字相同，因為第二份複本會漂。實測拿到的輸出裡「先前還出了測試」第二次變成
「先前才出的測試」，46 個字元有 2 個不一樣。辨識錯誤反而會被照抄（work train 兩次
一模一樣），真的用詞才會漂，所以逐字比對正好看不到這一種跳針。

門檻看的是「重覆的單位有多長」，不是「相同的總長度有多長」。「哈」×17 與
「不要」×9 相同的總長度很長，但重覆的單位只有一到兩個詞，那是正常的口語強調，
不是跳針。

長度一律用「詞」算，不用字元算：中文一個字算一個詞，連在一起的英數算一個詞。英文一個
詞平均五六個字元，所以 database connection pool 只有三個詞卻有 25 個字元，而 24 個
中文字是一整句話。用字元當單位會砍掉夾了英文術語的正常句子。

兩個門檻是一起量出來的，不是推理出來的。tests/measure_margins.py 拿 tests/test_deloop.py
的語料算兩側臨界，現在的數字是：

  單位長度  必須砍的最短 24 個詞，不可以砍的最長 23 個詞。MIN_SPAN 只能是 24，
            必須砍的那一邊一個詞都不剩，不可以砍的那一邊剩一個詞。
  字元相同  必須砍的最低 0.957，不可以砍的最高 0.929。RATIO 取兩者之間的 0.94，
            離必須砍的那一邊 0.017，離不可以砍的那一邊 0.011。

放寬成近似比對會把誤判的面積變大，擋住它的是 MIN_SPAN 而不是 RATIO：語料裡最像的
那一句正常句子（說到一半改口，把整個子句重講一次只改一個字）有 0.957 相同，是靠
23 個詞沒到 24 才活下來的。

要注意這個門檻在原理上並不安全：真人把超過 24 個詞的話再講一次、只改一兩個字，還是會
被砍掉。「請你提醒陳經理明天下午三點的會議要帶上一季的營收報表也請你提醒林經理……」
就是會被砍的形狀。寧可漏掉也不要砍到正常的句子，所以漏掉的那一邊不再補強。engine.log
每個 chunk 都記了辨識字數與砍掉後的字數，真的漏掉或砍錯時把那一句加進語料，重跑
measure_margins.py 再調門檻。
"""
import re

MIN_SPAN = 24  # 重覆單位至少這麼多詞才敢砍
MAX_GAP = 8    # 兩份複本之間容許的連接詞長度，這個用字元算，比較嚴
RATIO = 0.94   # 兩份複本對齊之後，至少這個比例的字元要逐字相同

_WORD = re.compile(r"[A-Za-z0-9_]+|\w")


def _words(s):
    """數詞：中文一個字一個詞，連在一起的英數算一個詞，標點與空白都不算。

    標點不算很重要。把點和底線各算一個詞的話，1.2.3 會算成五個詞、
    config_file_path 會算成五個詞，正常句子的引述就會被撐過門檻。
    """
    return len(_WORD.findall(s))


def _same_runs(text, d):
    """位移 d 之下每一段「連續相同」的區段，回傳 [(起點, 長度), ...]。"""
    runs, start, n = [], None, len(text) - d
    for x in range(n):
        if text[x] == text[x + d]:
            if start is None:
                start = x
        elif start is not None:
            runs.append((start, x - start))
            start = None
    if start is not None:
        runs.append((start, n - start))
    return runs


def _longest_repeat(text):
    """找出夠長、夠近也夠像的最長重覆段落，回傳 (起點, 位移, 長度)，找不到回 None。

    位移 d 是兩份複本起點的距離。固定 d 時，text[x] == text[x + d] 的那些區段就是這個
    位移下相同的部分。把相鄰的幾段串成一個區段，中間夾的就是第二份複本漂掉的字元；
    串起來的長度叫 total，d 減掉 total 就是兩份複本之間隔了幾個字。這個差可以是負的，
    代表兩份複本重疊，也就是同一段連著跳針三次以上。

    串起來的區段只從相同的字元起、也在相同的字元止。兩端放寬會往外吃到不相干的字，
    砍的位置就會跑掉；中間放寬只是容許第二份複本漂掉的那幾個字。

    重覆的單位是 min(d, total)：total 超過 d 時，重覆的單位就是那一個週期。
    一個單位至少佔一個字元，所以先用字元數擋掉絕大多數位置，再去數詞。
    """
    best = None
    for d in range(1, len(text)):
        runs = _same_runs(text, d)
        for i, (start, _) in enumerate(runs):
            same = 0
            for begin, run in runs[i:]:
                same += run
                total = begin + run - start
                if min(d, total) < MIN_SPAN or d - total > MAX_GAP:
                    continue
                if same < RATIO * total:
                    continue
                if best is not None and total <= best[2]:
                    continue
                if _words(text[start:start + min(d, total)]) >= MIN_SPAN:
                    best = (start, d, total)
    return best


def _tail_is_debris(tail, unit):
    """判斷重覆段落後面剩下的尾巴是不是跳針的碎屑。

    跳針停下來之前常再吐幾次重覆單位的開頭（「現在現在現在」裡的「現在」）。
    整條尾巴都能用 unit 的開頭拼完、而且拼出兩片以上才算碎屑；只拼出一片有可能是
    使用者接著講的話，留著。

    這裡仍然逐字比。拼不起來就當成使用者講的話留著，寧可留下垃圾也不要吃掉字。
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
        # start + shift 之後的每一個字元都對齊到它前面 shift 個字元，整段至少 RATIO
        # 相同，是第二份複本；只重覆一段（length < shift）時，前面多出來的那幾個字是
        # 連接詞。留下來的是第一份複本，所以兩份複本不一樣時，使用者拿到先講的那一版。
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
