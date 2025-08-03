#!/bin/bash

# ===================== Configuration ===================== #
BASE_MODEL="Qwen/Qwen2.5-1.5B-Instruct"

LORA_PATH="training_outputs/qwen-1.5B-instruct/agent_baseline_2epochs_250511_prefix"
MAX_LORA_RANK=64

PORT=8000
RETRIEVER_CONDA_ENV="retriever"
RETRIEVER_GPU_DEVICES="2,3"
RETRIEVER_LOG="retriever_server.log"
# ========================================================= #

# Cleanup handler
cleanup() {
  echo ""
  echo "🧹 Cleaning up retriever and vLLM..."
  # If the process is not cleaned well
  ps -eo pid,command \
    grep -E '/home/.*/conda/.*/bin/python(3(\.[0-9]+)?)?$' | grep 'vllm' \
    | grep -v grep | awk '{print $1}' | xargs kill
  pgrep -f 'retriever_server.py' | xargs -r kill
  wait
  echo "✅ Cleanup done."
}

# Trap Ctrl+C
trap 'echo ""; echo "❌ Interrupted!"; cleanup; exit 1' SIGINT SIGTERM
export VLLM_USE_V1=0

echo "🔍 Launching retriever in background..."
# Conda shell hook (MUST be before activate)
source "$(conda info --base)/etc/profile.d/conda.sh"
(
  conda activate "$RETRIEVER_CONDA_ENV"
  CUDA_VISIBLE_DEVICES=$RETRIEVER_GPU_DEVICES \
    python search/retriever_server.py > "$RETRIEVER_LOG" 2>&1 &
  RETRIEVER_PID=$!
  echo "🛰️  Retriever server started (PID: $RETRIEVER_PID, GPUs: $RETRIEVER_GPU_DEVICES)"
  conda deactivate
) &

# Wait briefly to ensure retriever has started
sleep 10

echo "🚀 Launching vLLM model in foreground on all GPUs..."
CMD="python serve_vllm.py \
  --model \"$BASE_MODEL\" \
  --port $PORT"

if [ -n "$LORA_PATH" ]; then
  CMD="$CMD --lora-modules finetune=$LORA_PATH --max-lora-rank $MAX_LORA_RANK"
fi

eval $CMD

cleanup
exit 0
