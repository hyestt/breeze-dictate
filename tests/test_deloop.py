#!/usr/bin/env python3
"""辨識結果的重覆段落要被砍掉，正常句子要原封不動。

LOOPED 的每一筆都是使用者實際拿到的輸出，重覆的那一段寫在 repeat 欄位。
CLEAN 用來擋住砍過頭，前六筆是辨識正確的句子，後面幾筆是手寫的，
每一筆都合理地重覆了一段用詞，專門用來擋住「看到重覆就砍」的實作。
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app" / "Resources"))
from deloop import deloop

LOOPED = [
    ("我剛剛測試了一下好像現在又可以了沒有出現剛剛的問題所以你可以先不用處理"
     "剛剛的問題好像現在又可以了沒有出現剛剛的問題所以你可以先不用處理",
     "好像現在又可以了沒有出現剛剛的問題所以你可以先不用處理"),
    ("就如你看到現在標點模型的模型好像沒有使用到所以它都是變成一長串"
     "現在標點模型的模型好像沒有使用到所以它都是變成一長串現在現在現在",
     "標點模型的模型好像沒有使用到所以它都是變成一長串"),
    ("那如果說我想要達到的效果跟 AirPods 一樣好的話還有什麼 microphone 是比較適合的"
     "是真的一定就得距離這麼遠嗎還是說有什麼鍵盤上面可以直接有 microphone該怎麼去處理那"
     "這個問題就得距離這麼遠嗎還是說有什麼鍵盤上面可以直接有 microphone該怎麼去處理那如果",
     "就得距離這麼遠嗎還是說有什麼鍵盤上面可以直接有 microphone該怎麼去處理那"),
]

CLEAN = [
    "我想說的是如果我們這一季真的要把這個產品推出去那麼在時程上面就必須要往前拉一個月"
    "而且測試的部分也要同時進行不然到最後一定會來不及",
    "我現在說繁體中文中間夾雜一些英文像是 Claude Code 很好用這種句子看看辨識的結果"
    "會不會把前面或後面的字吃掉如果會的話那就是我們要修的問題",
    "我昨天晚上花了三個小時在看那份報告裡面提到的幾個重點其實都跟我們上次討論的方向差不多",
    "這個功能什麼時候可以上線我想知道目前的進度大概到哪裡了",
    "今天天氣不錯",
    "這個月的業績比上個月好這個月的成本也比上個月低",
    # 強調：整段七個字連著講兩次。
    "你不要再問我了你不要再問我了我真的不知道答案",
    # 排比：兩句的開頭一模一樣，中間只隔五個字。
    "我希望這個功能可以早一點上線我希望這個功能可以更穩定",
    # 列舉：每一項都用同一組連接詞。
    "如果你想要快一點就用這個方法如果你想要穩一點就用那個方法",
    # 同一個人名在一句話裡出現兩次。
    "請你把這份資料寄給王小明然後也寄給王小明的助理",
    # 排比句的結尾一模一樣。
    "我們這次的目標是把辨識的速度再提升一點把辨識的準確度也再提升一點這樣使用起來才會順",
]


def main():
    failures = []

    for text, repeat in LOOPED:
        got = deloop(text)
        if got.count(repeat) != 1:
            failures.append(f"重覆沒砍乾淨：{repeat!r} 出現 {got.count(repeat)} 次\n  得到 {got!r}")
        elif not text.startswith(got[:20]):
            failures.append(f"開頭被動到了\n  原文 {text[:20]!r}\n  得到 {got[:20]!r}")

    for text in CLEAN:
        got = deloop(text)
        if got != text:
            failures.append(f"正常句子被砍了 {len(text)} -> {len(got)} 字\n  原文 {text!r}\n  得到 {got!r}")

    for line in failures:
        print("FAIL", line)
    total = len(LOOPED) + len(CLEAN)
    print(f"\n{total - len(failures)}/{total} 通過")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
