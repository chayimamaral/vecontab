#!/bin/bash

# Configurações
PROJECT_ID="vecontab"
REGION="us-central1"
REPO="vecontab-repo"
IMAGE_NAME="frontend"
BACKEND_URL="https://vecontab-backend-822119889622.us-central1.run.app"
FULL_IMAGE_PATH="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/$IMAGE_NAME:latest"

echo "🚀 Iniciando Deploy do Frontend: $IMAGE_NAME"

# 1. Build da Imagem com a URL do Backend injetada
echo "📦 Gerando build da imagem Docker..."
docker build --no-cache \
  --build-arg NEXT_PUBLIC_API_URL=$BACKEND_URL \
  -t $FULL_IMAGE_PATH .

# 2. Push para o Google Artifact Registry
echo "📤 Enviando imagem para o Google Cloud..."
docker push $FULL_IMAGE_PATH

# 3. Deploy no Cloud Run
echo "🌍 Atualizando serviço no Cloud Run..."
gcloud run deploy vecontab-frontend \
  --image $FULL_IMAGE_PATH \
  --region $REGION \
  --allow-unauthenticated \
  --port 8080

echo "✅ Deploy finalizado com sucesso!"