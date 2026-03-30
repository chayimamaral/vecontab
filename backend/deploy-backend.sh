#!/bin/bash

# Configurações
PROJECT_ID="vecontab"
REGION="us-central1"
REPO="vecontab-repo"
IMAGE_NAME="backend"
FULL_IMAGE_PATH="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/$IMAGE_NAME:latest"

echo "🚀 Iniciando Deploy do Backend: $IMAGE_NAME"

# 1. Build da Imagem
echo "📦 Gerando build da imagem Docker (Go)..."
docker build -t $FULL_IMAGE_PATH .

# 2. Push para o Google Artifact Registry
echo "📤 Enviando imagem para o Google Cloud..."
docker push $FULL_IMAGE_PATH

# 3. Deploy no Cloud Run
echo "🌍 Atualizando serviço no Cloud Run..."
gcloud run deploy vecontab-backend \
  --image $FULL_IMAGE_PATH \
  --region $REGION \
  --allow-unauthenticated

echo "✅ Deploy do Backend finalizado!"