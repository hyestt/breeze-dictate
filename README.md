# Breeze 語音輸入（macOS）

按住一個鍵說話，放開後把**繁體中文（可夾英文）**貼到游標處。
使用 [Breeze-ASR-25 MLX 5-bit](https://huggingface.co/MarkChen1214/Breeze-ASR-25-MLX-5bit) 在本機轉錄，不上傳任何聲音。

- 按鍵：**右 Option**（Windows 鍵盤是右 Alt），按住說話、放開貼上
- 速度：短句約 0.1–0.5 秒（M 系列晶片）
- 輸出：用 OpenCC 轉成台灣繁體與台灣用語
- 詞表：`replacements.json` 修正常聽錯的詞（例：`cloud` → `Claude`）

## 需求

- Apple Silicon Mac（M1 以上）
- [uv](https://docs.astral.sh/uv/)：`brew install uv`
- Xcode 命令列工具：`xcode-select --install`
- 約 2 GB 磁碟空間

## 安裝（約 5 分鐘）

```sh
git clone <本 repo 網址> ~/breeze-dictate
cd ~/breeze-dictate
./install.sh
```

腳本會建立環境、下載模型、建立 `BreezeDictate.app` 並設為開機自動啟動。
最後請依畫面指示，到系統設定替 **BreezeDictate.app** 開啟三項授權（無法由程式代開）：

1. 輔助使用（新版 macOS 叫 Device Control and Data Access）
2. 輸入監控
3. 麥克風（第一次錄音時會跳出詢問）

授權完執行 `launchctl kickstart -k gui/$(id -u)/com.breeze-dictate`，再按住右 Option 說話。

## 自訂

- 換按鍵：改 `dictate.py` 的 `HOTKEY`，再重啟服務。
- 加詞：編輯 `replacements.json`（`"正確寫法": ["常聽錯的寫法", ...]`），再重啟服務。
- 注意：詞表會把所有 `cloud` 換成 `Claude`；若你常講 cloud computing，請從表中移除。
- 看紀錄：`tail -f dictate.log`

## 已知限制

- 標點很少，這是模型特性。
- 英文術語偶爾聽錯，用詞表補。
- 講完後模型偶爾會重念開頭；程式已限制長度並截掉重複，仍可能漏網。
- 每次重跑 `install.sh` 會重建 App，macOS 可能要求重新授權。

## 移除

```sh
./uninstall.sh
```

## 授權

本程式 MIT。模型 Breeze-ASR-25 由 MediaTek Research 發布（Apache-2.0），MLX 5-bit 為社群轉換。
