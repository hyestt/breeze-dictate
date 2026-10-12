#!/bin/zsh
# 首次啟動時安裝引擎：uv、Python 3.12、套件、模型。可重複執行，已完成的步驟會略過。
# 用法：bootstrap.sh <支援資料夾> <App 內 Resources 路徑> [core|punctuation]
# core（預設）安裝語音引擎；punctuation 在既有引擎環境上加裝標點模型。
# 進度以「STEP n/m 說明」逐行輸出；失敗時結束碼非 0，最後一行是原因。
set -euo pipefail
SUP="$1"; RES="$2"; MODE="${3:-core}"
mkdir -p "$SUP/bin"
export UV_INSTALL_DIR="$SUP/bin" UV_NO_MODIFY_PATH=1 UV_PYTHON_INSTALL_DIR="$SUP/python" UV_CACHE_DIR="$SUP/cache"
UV="$SUP/bin/uv"

if [[ "$MODE" == "punctuation" ]]; then
  if [[ ! -x "$UV" || ! -x "$SUP/venv/bin/python" ]]; then
    echo "請先安裝語音引擎，再安裝標點模型"; exit 1
  fi
  echo "STEP 1/2 安裝標點套件 mlx-lm"
  "$UV" pip install -q --python "$SUP/venv/bin/python" "mlx-lm==0.32.0"
  echo "STEP 2/2 下載標點模型（約 1 GB，需要幾分鐘）"
  # 先下載到暫存夾再改名，中斷時不會留下半套被誤認為已安裝的 punct-model。
  export HF_HUB_DISABLE_PROGRESS_BARS=1
  rm -rf "$SUP/punct-model.part"
  "$SUP/venv/bin/python" -c "from huggingface_hub import snapshot_download as d; d('mlx-community/Qwen3-1.7B-4bit', local_dir='$SUP/punct-model.part')"
  rm -rf "$SUP/punct-model"
  mv "$SUP/punct-model.part" "$SUP/punct-model"
  echo "DONE"
  exit 0
fi
[[ "$MODE" == "core" ]] || { echo "未知的模式：$MODE"; exit 2; }

echo "STEP 1/4 下載安裝工具 uv"
[[ -x "$UV" ]] || curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null

echo "STEP 2/4 建立 Python 3.12 環境"
[[ -x "$SUP/venv/bin/python" ]] || "$UV" venv --python 3.12 "$SUP/venv" -q

echo "STEP 3/4 安裝辨識套件"
"$UV" pip install -q --python "$SUP/venv/bin/python" -r "$RES/requirements.txt"

echo "STEP 4/4 下載語音模型（約 1 GB，需要幾分鐘）"
if [[ ! -f "$SUP/model/model.safetensors" ]]; then
  "$SUP/venv/bin/python" -c "from huggingface_hub import snapshot_download as d; d('MarkChen1214/Breeze-ASR-25-MLX-5bit', local_dir='$SUP/model')"
fi
echo "DONE"
