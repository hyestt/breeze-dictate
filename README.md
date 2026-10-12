# Breeze 語音輸入（macOS）

按住一個鍵說話，放開後把**繁體中文（可夾英文）**貼到游標處。
在本機用 [Breeze-ASR-25 MLX 5-bit](https://huggingface.co/MarkChen1214/Breeze-ASR-25-MLX-5bit) 辨識，聲音不會上傳。

- 預設快捷鍵：**右 Option**（Windows 鍵盤是右 Alt），可在設定改成其他鍵
- 速度：短句約 0.1 到 0.5 秒（Apple Silicon）
- 輸出：台灣繁體與台灣用語
- 自動加標點（選用）：辨識後用本機小型語言模型補標點，預設關閉
- 詞彙表：在 App 內新增常聽錯的詞，例如把 `cloud` 改成 `Claude`

## 需求

- Apple Silicon Mac（M1 以上），macOS 14 以上
- Xcode 命令列工具：`xcode-select --install`
- 網路連線與約 3 GB 磁碟空間（開啟自動加標點再加 1 GB）

## 安裝

這個 App 沒有 Apple 付費開發者簽章，所以**自己建置比下載現成檔案順**。自己建的 App 不帶「從網路下載」標記，macOS 不會攔。

### 1. 先建立簽署憑證（強烈建議）

跳過這步也能用，但之後每次重新建置，macOS 都會當成不同的 App，三項授權都要重設一次。

1. 開啟「鑰匙圈存取」，選單「鑰匙圈存取 → 憑證輔助程式 → 建立憑證」。
2. 名稱填 `BreezeDictate Local Signing`，身分類型選「自簽的根憑證」，憑證類型選「程式碼簽署」，按「建立」。

憑證只留在你自己的電腦上，不會上傳。建置腳本會自動找到它，也可以用環境變數 `BREEZE_SIGN_ID` 指定別的名稱。

### 2. 建置並安裝

```sh
git clone https://github.com/hyestt/breeze-dictate
cd breeze-dictate
./scripts/build_app.sh
rm -rf /Applications/BreezeDictate.app
ditto build/BreezeDictate.app /Applications/BreezeDictate.app
open /Applications/BreezeDictate.app
```

以後要更新，`git pull` 之後再執行一次 `./scripts/build_app.sh` 就好。腳本會自動同步「應用程式」裡那份。

### 3. 首次設定

App 會自己開啟「首次設定」視窗：

1. 按「開始安裝」，等語音引擎與模型下載完成（約 1 GB，需要幾分鐘）。
2. 在「輔助使用」與「輸入監控」按「前往授權」，到系統設定打開 BreezeDictate 的開關。
3. 麥克風會在第一次錄音時跳出詢問，按「允許」。
4. 三項都允許後，**結束 App 再重新開啟一次**，全域按鍵監聽才會生效。

### 4. 使用

游標放進任何輸入框，按住快捷鍵說話，放開。文字會貼到游標處。

## 設定

點選單列的麥克風圖示，選「設定…」。

- **一般：** 錄製新快捷鍵、開機自動啟動、提示音、自動加標點。
- **自動加標點：** 辨識模型輸出沒有標點。打開開關會額外下載約 1 GB 的 Qwen3-1.7B 模型（每句約 0.2 秒）。模型只加標點；若偵測到有字被改動，會自動退回沒有標點的版本。少於 4 個字不處理。關閉後引擎重啟並釋放記憶體，要收回磁碟空間請按「移除標點模型」。
- **詞彙：** 左欄填正確寫法，右欄填常聽錯的寫法（逗號分隔）。改完立刻生效。
- **注意：** 詞彙表會把所有 `cloud` 換成 `Claude`。如果你常講 cloud computing，請從表中移除。

## 疑難排解

- **按了完全沒反應：** 到設定的「一般」分頁看三項授權是否都是「已允許」。都允許卻還是沒反應，結束 App 再開一次。授權是在 App 啟動時讀取的。
- **授權清單裡找不到 BreezeDictate：** 系統設定頁沒有重新整理，關掉再開一次。
- **開頭幾個字被吃掉：** 麥克風休眠後第一次喚醒要約 100 毫秒，藍牙耳機更久。先快速按一下放開（短於 0.35 秒不會送去辨識，只喚醒麥克風），再按住說話。
- **只出現一兩個字，或顯示「沒有收到聲音」：** 系統的輸入裝置換過了。到「系統設定 → 聲音 → 輸入」確認選的是你正在用的麥克風。
- **最後幾個字被切掉：** 放開按鍵後程式會多錄 0.45 秒，正常不會發生。若仍會，說完停頓一下再放開。
- **看紀錄：** `~/Library/Application Support/BreezeDictate/app.log` 與 `engine.log`。紀錄只有狀態與字數，不含你說的內容。

## 隱私

- 辨識全程在本機，不上傳聲音或文字；補標點也在本機執行。
- 錄音存在暫存檔，辨識完立刻刪除。
- 只有安裝時會連網，下載 uv、Python 套件與模型（含選用的標點模型）。

## 開發

設計、資料格式與引擎協定見 [`app/DESIGN.md`](app/DESIGN.md)。

- Swift 原始碼在 `app/Sources/`，辨識引擎在 `app/Resources/engine.py`。
- `BREEZE_NO_INSTALL=1 ./scripts/build_app.sh` 只建置，不動「應用程式」裡那份。
- `BREEZE_SUPPORT_DIR=/path/to/test` 可以把資料夾換到別處測試，不影響正式資料。

## 移除

1. 結束 App，把它從「應用程式」刪掉。
2. 刪除 `~/Library/Application Support/BreezeDictate`（含模型，約 3 GB；若裝過標點模型再加約 1 GB）。
3. 在系統設定的輔助使用、輸入監控、麥克風，移除 BreezeDictate。

## 授權

程式採 MIT。模型 Breeze-ASR-25 由 MediaTek Research 發布（Apache-2.0），MLX 5-bit 為社群轉換。
