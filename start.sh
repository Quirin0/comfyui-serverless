#!/usr/bin/env bash

echo "=== Worker Initiated ==="

# Debug paths
echo "Debug: Listando pastas comuns..."
ls -la /workspace 2>/dev/null || echo "workspace não existe"
ls -la /comfyui 2>/dev/null || echo "comfyui não existe"
ls -la /app 2>/dev/null || echo "app não existe"
ls -la /opt 2>/dev/null || echo "opt não existe"

# Procura o main.py do ComfyUI
COMFY_ROOT=$(find / -name main.py 2>/dev/null | grep ComfyUI | head -n 1 | xargs dirname 2>/dev/null)
if [ -z "$COMFY_ROOT" ]; then
  echo "ERRO: main.py do ComfyUI não encontrado em nenhum lugar!"
  exit 1
fi

echo "ComfyUI encontrado em: $COMFY_ROOT"

# Symlinking do storage
echo "Symlinking custom_nodes and models from Network Volume"
STORAGE_PATH="/runpod-volume/runpod-slim/ComfyUI"  # ajuste se necessário

# Custom Nodes
if [ -d "$STORAGE_PATH/custom_nodes" ]; then
  echo "Criando symlinks para custom_nodes..."
  mkdir -p "$COMFY_ROOT/custom_nodes"
  for item in "$STORAGE_PATH/custom_nodes/"*; do
    dest="$COMFY_ROOT/custom_nodes/$(basename "$item")"
    [ -L "$dest" ] && rm -f "$dest"
    ln -sf "$item" "$dest"
    echo "Symlink criado: $(basename "$item")"
  done
else
  echo "Pasta custom_nodes não encontrada: $STORAGE_PATH/custom_nodes"
fi

# Models
if [ -d "$STORAGE_PATH/models" ]; then
  echo "Criando symlinks para models..."
  mkdir -p "$COMFY_ROOT/models"
  for item in "$STORAGE_PATH/models/"*; do
    dest="$COMFY_ROOT/models/$(basename "$item")"
    [ -L "$dest" ] && rm -f "$dest"
    ln -sf "$item" "$dest"
    echo "Symlink criado em models: $(basename "$item")"
  done
else
  echo "Pasta models não encontrada: $STORAGE_PATH/models"
fi

echo "Symlinks concluídos!"

# Inicia ComfyUI
echo "Starting ComfyUI API in $COMFY_ROOT"
export PYTHONUNBUFFERED=true
export HF_HOME="/runpod-volume/hf_cache"

TCMALLOC=$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)
[ -n "$TCMALLOC" ] && export LD_PRELOAD="${TCMALLOC}"

cd "$COMFY_ROOT" || { echo "Erro ao cd para $COMFY_ROOT"; exit 1; }
python main.py \
  --port 3000 \
  --temp-directory /tmp \
  --listen 0.0.0.0 \
  > /tmp/comfyui-serverless.log 2>&1 &

# Aguarda API
echo "Aguardando ComfyUI API..."
for i in {1..60}; do
  if curl -s http://127.0.0.1:3000/system_stats > /dev/null; then
    echo "ComfyUI API pronta!"
    break
  fi
  sleep 1
done

echo "Starting Runpod Handler"
python3 -u /handler.py