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
- 網路連線（首次安裝要下載約 1 GB 的模型）與約 3 GB 磁碟空間

## 安裝

這個 App 沒有 Apple 付費開發者簽章，所以**自己建置比下載現成檔案順**。自己建的 App 不帶「從網路下載」標記，macOS 不會攔。

需要 Xcode 命令列工具，沒裝的話執行 `xcode-select --install`。

```sh
git clone https://github.com/hyestt/breeze-dictate
cd breeze-dictate
./scripts/build_app.sh
cp -R build/BreezeDictate.app /Applications/
open /Applications/BreezeDictate.app
```

接著跟著「首次設定」視窗做：

1. 按「開始安裝」，等引擎與模型下載完成（約 1 GB，需要幾分鐘）。
2. 在「輔助使用」與「輸入監控」按「前往授權」，到系統設定打開 BreezeDictate 的開關。麥克風會直接跳出詢問，按「允許」。
3. 三項都打勾後，**結束 App 再重新開啟一次**，授權才會生效。
4. 游標放進任何輸入框，按住快捷鍵說話，放開。

### 建立固定簽署憑證（建議）

沒有憑證時，每次重新建置 macOS 都會當成不同的 App，三項授權都要重設一次。建一個本機憑證就不會：

1. 開啟「鑰匙圈存取」，選單「鑰匙圈存取 → 憑證輔助程式 → 建立憑證」。
2. 名稱填 `BreezeDictate Local Signing`，身分類型選「自簽的根憑證」，憑證類型選「程式碼簽署」，建立。
3. 重新執行 `./scripts/build_app.sh`，腳本會自動找到並使用它。

憑證只留在你自己的電腦上，不會上傳。

## 設定

點選單列的麥克風圖示，選「設定…」。

- **一般：** 錄製新快捷鍵、開機自動啟動、提示音、自動加標點。
- **自動加標點：** 辨識模型輸出沒有標點。打開開關會額外下載約 1 GB 的 Qwen3-1.7B 模型（每句約 0.2 秒）。模型只加標點；若偵測到有字被改動，會自動退回沒有標點的版本。少於 4 個字不處理。關閉後引擎重啟並釋放記憶體，要收回磁碟空間請按「移除標點模型」。
- **詞彙：** 左欄填正確寫法，右欄填常聽錯的寫法（逗號分隔）。改完立刻生效。
- **注意：** 詞彙表會把所有 `cloud` 換成 `Claude`。如果你常講 cloud computing，請從表中移除。

## 疑難排解

- **按了沒反應：** 到設定的「一般」分頁看三項授權是否都是「已允許」，再結束並重開 App。
- **授權清單裡找不到 BreezeDictate：** 設定頁沒有重新整理，關掉系統設定再開一次。
- **開頭的字被吃掉：** 按下後直接說，不用等；若仍會發生，請開 issue 並附上環境。
- **看紀錄：** `~/Library/Application Support/BreezeDictate/app.log` 與 `engine.log`。紀錄只有狀態，不含你說的內容。

## 隱私

- 辨識全程在本機，不上傳聲音或文字；補標點也在本機執行。
- 錄音存在暫存檔，辨識完立刻刪除。
- 只有安裝時會連網，下載 uv、Python 套件與模型（含選用的標點模型）。

## 從原始碼建置

需要 Xcode 命令列工具（`xcode-select --install`）。

```sh
git clone https://github.com/hyestt/breeze-dictate
cd breeze-dictate
./scripts/build_app.sh   # 產出 build/BreezeDictate.app 與 zip
```

建議先建立固定的本機簽署憑證，名稱 `BreezeDictate Local Signing`（或用環境變數 `BREEZE_SIGN_ID` 指定）。沒有憑證會退回 ad-hoc 簽署，這時**每次重建都要重新授權**。

設計與資料格式見 [`app/DESIGN.md`](app/DESIGN.md)。

## 移除

1. 結束 App，把它從「應用程式」刪掉。
2. 刪除 `~/Library/Application Support/BreezeDictate`（含模型，約 3 GB；若裝過標點模型再加約 1 GB）。
3. 在系統設定的輔助使用、輸入監控、麥克風，移除 BreezeDictate。

## 授權

程式採 MIT。模型 Breeze-ASR-25 由 MediaTek Research 發布（Apache-2.0），MLX 5-bit 為社群轉換。
