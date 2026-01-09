#!/usr/bin/env bash

echo "=== Worker Initiated ==="

# 1. Symlink do storage para o path que o ComfyUI espera (se necessário)
# (seu storage já está montado em /runpod-volume, não precisa rm -rf /workspace)
echo "Symlinking custom_nodes and models from Network Volume"

STORAGE_PATH="/runpod-volume/runpod-slim/ComfyUI"  # ajuste se o path for diferente
COMFY_ROOT="/comfyui"  # path real do template ashleykleynhans

# Custom Nodes
if [ -d "$STORAGE_PATH/custom_nodes" ]; then
  echo "Criando symlinks para custom_nodes..."
  for item in "$STORAGE_PATH/custom_nodes/"*; do
    dest="$COMFY_ROOT/custom_nodes/$(basename "$item")"
    [ -L "$dest" ] && rm -f "$dest"  # remove symlink antigo se existir
    ln -sf "$item" "$dest"
    echo "Symlink criado: $(basename "$item")"
  done
else
  echo "Pasta custom_nodes não encontrada no storage: $STORAGE_PATH/custom_nodes"
fi

# Models (checkpoints, loras, vae, etc.)
if [ -d "$STORAGE_PATH/models" ]; then
  echo "Criando symlinks para models..."
  for item in "$STORAGE_PATH/models/"*; do
    dest="$COMFY_ROOT/models/$(basename "$item")"
    [ -L "$dest" ] && rm -f "$dest"
    ln -sf "$item" "$dest"
    echo "Symlink criado em models: $(basename "$item")"
  done
else
  echo "Pasta models não encontrada no storage: $STORAGE_PATH/models"
fi

echo "Symlinks concluídos!"

# 2. Inicia o ComfyUI diretamente (sem venv, pois o template usa o Python do sistema)
echo "Starting ComfyUI API"
export PYTHONUNBUFFERED=true
export HF_HOME="/runpod-volume/hf_cache"  # cache do HuggingFace no storage (opcional, evita redownload)

# TCMalloc para melhor memória (se disponível)
TCMALLOC=$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)
if [ -n "$TCMALLOC" ]; then
  export LD_PRELOAD="${TCMALLOC}"
fi

# Inicia o ComfyUI em background
cd "$COMFY_ROOT" || { echo "Erro: pasta $COMFY_ROOT não encontrada!"; exit 1; }
python main.py \
  --port 3000 \
  --temp-directory /tmp \
  --listen 0.0.0.0 \
  > /tmp/comfyui-serverless.log 2>&1 &

# Aguarda o ComfyUI iniciar (até 60 segundos)
echo "Aguardando ComfyUI API iniciar..."
for i in {1..60}; do
  if curl -s http://127.0.0.1:3000/system_stats > /dev/null; then
    echo "ComfyUI API está pronta!"
    break
  fi
  sleep 1
done

# 3. Inicia o handler do RunPod
echo "Starting Runpod Handler"
python3 -u /handler.py