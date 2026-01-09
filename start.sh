#!/usr/bin/env bash

echo "=== Worker Initiated ==="

# COMFY_ROOT é o diretório atual (raiz do repo clonado no GitHub)
COMFY_ROOT="."

echo "ComfyUI está na raiz do container: $COMFY_ROOT (conteúdo do seu GitHub)"

# Path completo do storage com o "workspace/" que faltava
STORAGE_PATH="/runpod-volume/workspace/runpod-slim/ComfyUI"

echo "Procurando custom nodes e models no storage: $STORAGE_PATH"

# Debug rápido para confirmar se o path existe
if [ -d "$STORAGE_PATH" ]; then
  echo "Storage encontrado! Conteúdo:"
  ls -la "$STORAGE_PATH"
else
  echo "ERRO: Pasta não encontrada no storage: $STORAGE_PATH"
  echo "Verifique se o path está correto (rode ls /runpod-volume/workspace no Pod)"
fi

# Symlinking custom_nodes
if [ -d "$STORAGE_PATH/custom_nodes" ]; then
  echo "Criando symlinks para custom_nodes..."
  mkdir -p "$COMFY_ROOT/custom_nodes"  # Cria se não existir
  for item in "$STORAGE_PATH/custom_nodes/"*; do
    dest="$COMFY_ROOT/custom_nodes/$(basename "$item")"
    [ -L "$dest" ] && rm -f "$dest"  # Remove symlink antigo
    ln -sf "$item" "$dest"
    echo "Symlink criado: $(basename "$item")"
  done
else
  echo "Pasta custom_nodes não encontrada: $STORAGE_PATH/custom_nodes"
fi

# Symlinking models
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

# Inicia ComfyUI na raiz do repo
echo "Starting ComfyUI API na raiz"
export PYTHONUNBUFFERED=true
export HF_HOME="/runpod-volume/hf_cache"  # Cache do HuggingFace no storage

TCMALLOC=$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)
[ -n "$TCMALLOC" ] && export LD_PRELOAD="${TCMALLOC}"

cd "$COMFY_ROOT" || { echo "Erro cd para raiz"; exit 1; }
python main.py \
  --port 3000 \
  --temp-directory /tmp \
  --listen 0.0.0.0 \
  > /tmp/comfyui-serverless.log 2>&1 &

# Aguarda a API iniciar (até 60 segundos)
echo "Aguardando ComfyUI API iniciar..."
for i in {1..60}; do
  if curl -s http://127.0.0.1:3000/system_stats > /dev/null; then
    echo "ComfyUI API pronta!"
    break
  fi
  sleep 1
done

echo "Starting Runpod Handler"
python3 -u /handler.py  # ou rp_handler.py se for o nome no seu repo