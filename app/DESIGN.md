# BreezeDictate.app 設計合約

選單列 App（LSUIElement）。Swift 負責所有需要系統授權的事，Python 引擎只做辨識，不需授權。

## 資料與路徑

支援資料夾 `SUP = ~/Library/Application Support/BreezeDictate/`

| 路徑 | 擁有者 | 內容 |
|---|---|---|
| `SUP/settings.json` | Swift | `{"hotkeyKeyCode":61,"hotkeyIsModifier":true,"hotkeyLabel":"右 Option","launchAtLogin":false,"playSound":true}` |
| `SUP/vocabulary.json` | Swift 寫、引擎讀 | `[{"target":"Claude","variants":["cloud","克勞德"]}]`（陣列，順序即顯示順序） |
| `SUP/venv`, `SUP/model`, `SUP/bin/uv` | bootstrap.sh | 引擎環境 |
| `App/Contents/Resources/{engine.py,bootstrap.sh,requirements.txt,default_vocabulary.json}` | 已存在（除 default_vocabulary.json 外） | 隨 App 附帶 |

首次啟動若 `vocabulary.json` 不存在，複製 `default_vocabulary.json`（內容取自 repo 根目錄 `replacements.json`，轉成陣列格式）。

## 引擎合約（已實作、已實測）

- 啟動：`SUP/venv/bin/python -u Resources/engine.py --model SUP/model --vocab SUP/vocabulary.json`，stdin/stdout 為 JSON 行，stderr 丟棄或寫 log。
- 先收到 `{"ready":true}`（載入約 3–10 秒），之後每行請求 `{"id":n,"wav":"/abs/path.wav"}`，回 `{"id":n,"text":"…","seconds":0.12}` 或 `{"id":n,"error":"…"}`。
- WAV 必須是 16 kHz、單聲道。引擎每次請求都會檢查 vocabulary.json 的修改時間並重載，所以改詞彙不需重啟。
- 引擎行程意外結束要自動重啟（最多連續 3 次，間隔遞增），並在選單顯示狀態。
- bootstrap：`/bin/zsh Resources/bootstrap.sh SUP Resources`，stdout 逐行 `STEP n/4 …`，最後 `DONE`；結束碼非 0 代表失敗，最後一行是原因。

## 行為

1. 按住快捷鍵開始錄音（AVAudioRecorder，16 kHz、單聲道、PCM16，寫到暫存 wav），放開即停止、送引擎、把結果貼到游標處。
2. 貼上：存下剪貼簿原內容，寫入文字，用 CGEvent 送 Cmd+V，約 0.3 秒後還原剪貼簿。需要輔助使用授權。
3. 少於 0.3 秒的錄音忽略。錄音中再按無效。處理完刪暫存檔。
4. 快捷鍵：預設右 Option（keyCode 61，修飾鍵）。支援單一修飾鍵（左右分開判斷，用 `flagsChanged` 加 keyCode）和一般鍵／F 鍵（`keyDown`/`keyUp`，忽略 key repeat）。用 `NSEvent.addGlobalMonitorForEvents`（需輸入監控）。設定頁有「錄製快捷鍵」按鈕：進入錄製狀態後按下的第一個鍵就是新快捷鍵，Esc 取消。
5. 開始、結束錄音可播放系統音效（Tink／Pop），由 `playSound` 控制。
6. 選單列圖示（SF Symbols）：待機 `mic`、錄音中 `mic.fill`（紅）、辨識中 `waveform`、引擎未就緒或缺授權 `exclamationmark.triangle`。選單項目：狀態文字、設定…、結束。

## 視窗（SwiftUI，繁體中文，台灣用語）

- **首次設定**（`engineReady == false` 或缺授權時自動出現）：三步。①「安裝語音引擎」按鈕，顯示 STEP 進度與失敗訊息、可重試；②「授權」逐項顯示麥克風、輔助使用、輸入監控的狀態（已允許／未允許），每項有按鈕：麥克風呼叫 `AVCaptureDevice.requestAccess`，其餘開對應系統設定頁並呼叫 `AXIsProcessTrustedWithOptions`／`CGRequestListenEventAccess`；每秒輪詢更新；③「試試看」：說明按住哪個鍵。全部完成後可關閉。
- **設定**（選單「設定…」）：分頁「一般」（快捷鍵錄製、開機自動啟動 `SMAppService.mainApp`、音效開關、授權狀態）、「詞彙」（表格：正確寫法＋常聽錯寫法〔逗號分隔〕；新增、刪除、編輯；寫入即存檔；附一行說明「例：Claude ← cloud, 克勞德」）、「關於」（版本、模型名稱與授權、專案網址 https://github.com/hyestt/breeze-dictate）。
- 開視窗時 `NSApp.setActivationPolicy(.regular)`，全部關閉後切回 `.accessory`。

## 結構要求

- 用一個 `Settings` 與 `Vocabulary` 的 Codable 型別，載入失敗退回預設值，不 crash。
- 狀態用 enum（`idle / recording / transcribing / error`）與 `EngineState`（`notInstalled / installing / starting / ready / failed`）表達，不要用散落的布林。
- 檔案分開：`App.swift`、`Settings.swift`、`Hotkey.swift`、`Recorder.swift`、`Engine.swift`、`Paster.swift`、`Permissions.swift`、`Views/*.swift`。
- 不加第三方套件。只用系統框架。Swift 6 語言模式遇到並行檢查太硬時用 Swift 5 模式（`-swift-version 5`）。
- 註解只寫非顯而易見的原因。

## 打包

`scripts/build_app.sh`：用 `swiftc` 編譯 `app/Sources/**/*.swift` 為 arm64 執行檔（最低 macOS 14），組出 `build/BreezeDictate.app`：`Info.plist`（`CFBundleIdentifier=com.hyestt.breeze-dictate`、`LSUIElement`、`NSMicrophoneUsageDescription`、`LSMinimumSystemVersion=14.0`、版本取自 `VERSION` 檔，先建 `VERSION` 內容 `0.1.0`）、把 `app/Resources/*` 複製進 `Contents/Resources`、圖示、ad-hoc 簽署（`codesign --force --deep -s -`）。再輸出 `build/BreezeDictate-<版本>.zip`（`ditto -c -k --keepParent`）。圖示：用腳本內嵌的 Swift 或 Python（系統內建，不依賴 PIL）畫一個圓角方形加麥克風符號，產生 `.icns`（`iconutil`）。`build/` 加入 `.gitignore`。

## 驗收

- `scripts/build_app.sh` 一次成功，`codesign -v build/BreezeDictate.app` 通過。
- 啟動 App 後 `pgrep BreezeDictate` 有行程；已有 SUP 環境時，引擎在 15 秒內 ready（可用 log 或選單狀態證明）。
- 不要動 `~/breeze-dictate` 目前執行中的舊服務（launchd `com.glen.breeze-dictate`）。測試時用 `SUP` 的暫時替代（環境變數 `BREEZE_SUPPORT_DIR` 可覆寫 SUP；預設為上表路徑）。
- 無法由 agent 自行驗證的（真人按鍵、授權視窗）要明說，不假裝驗證。
