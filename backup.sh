#!/bin/bash

# Define a raiz do projeto baseada na localização DESTE script
# Assumindo que o backup.sh está na raiz do vecontab
RAIZ_PROJETO=$(cd "$(dirname "$0")" && pwd)

# Configurações de Destino
BACKUP_DIR="$HOME/backups/vecontab"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="vecontab_source_$(date +%Y%m%d_%H%M%S).tar.gz"

echo "-------------------------------------------"
echo "💾 GERANDO BACKUP EM: $RAIZ_PROJETO"
echo "-------------------------------------------"

# -C $RAIZ_PROJETO: Entra na pasta do projeto antes de começar
# . : Compacta TUDO o que está lá dentro (incluindo o que o git ignore esconde)
tar -czf "$BACKUP_DIR/$BACKUP_FILE" \
    --exclude='./backend/node_modules' \
    --exclude='./frontend/node_modules' \
    --exclude='./frontend/.next' \
    --exclude='./.git' \
    --exclude='./backend/bin' \
    -C "$RAIZ_PROJETO" .

if [ $? -eq 0 ]; then
    echo "✅ Backup completo criado: $BACKUP_FILE"
    # Limpeza: mantém os 10 mais recentes
    (cd "$BACKUP_DIR" && ls -t vecontab_source_*.tar.gz | tail -n +11 | xargs rm -f 2>/dev/null)
else
    echo "⚠️ Falha ao gerar o arquivo de backup."
    exit 1
fi

