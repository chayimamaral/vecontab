#!/bin/bash

# Não usamos set -e aqui para podermos fazer o resumo final mesmo com falhas
BACKUP_DIR="$HOME/develop/go/vecontab/backup"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="vecontab_$(date +%Y%m%d_%H%M%S).tar.gz"

echo "-------------------------------------------"
echo "💾 GERANDO BACKUP DO CÓDIGO FONTE"
echo "-------------------------------------------"

# O git archive ignora node_modules, .next e binários automaticamente
if git archive --format=tar.gz -o "$BACKUP_DIR/$BACKUP_FILE" HEAD; then
    echo "✅ Backup criado: $BACKUP_FILE"
    # Mantém apenas os últimos 10 backups para não lotar o SSD
    (cd "$BACKUP_DIR" && ls -t vecontab_*.tar.gz | tail -n +11 | xargs rm -f 2>/dev/null)
else
    echo "⚠️ Falha ao gerar backup local. Verifique se há alterações não commitadas."
fi
echo "-------------------------------------------"

echo ""


if ! systemctl is-active --quiet docker; then
    echo "❌ ERRO: O serviço Docker não está rodando no Fedora."
    echo "Execute: sudo systemctl start docker"
    exit 1
fi

set +e

START_TIME=$(date +%s)
START_DATE=$(date +"%H:%M:%S")

# Arquivos para log completo (ajuda a diagnosticar depois no Fedora)
BACKEND_LOG=$(mktemp)
FRONTEND_LOG=$(mktemp)

echo ""
echo "--- Iniciando Deploy Global [Início: $START_DATE] ---"
echo "Log detalhado em: $BACKEND_LOG e $FRONTEND_LOG"
echo ""

# --- Executa backend ---
echo "📦 Processando Backend..."
# Rodamos o script e capturamos toda a saída (stdout + stderr)
if (cd backend && ./deploy-backend.sh > "$BACKEND_LOG" 2>&1); then
    BACKEND_STATUS="✅ Sucesso"
else
    BACKEND_STATUS="❌ FALHOU"
fi
# Mostra o status imediato no terminal para você não ficar no escuro
echo "Status: $BACKEND_STATUS"

echo ""

# --- Executa frontend ---
echo "🎨 Processando Frontend..."
if (cd frontend && ./deploy-frontend.sh > "$FRONTEND_LOG" 2>&1); then
    FRONTEND_STATUS="✅ Sucesso"
else
    FRONTEND_STATUS="❌ FALHOU"
fi
echo "Status: $FRONTEND_STATUS"

echo ""

# Cálculos de tempo...
END_TIME=$(date +%s)
END_DATE=$(date +"%H:%M:%S")
ELAPSED=$(( END_TIME - START_TIME ))
MINUTES=$(( ELAPSED / 60 ))
SECONDS=$(( ELAPSED % 60 ))

# --- RESUMO FINAL ---
echo "-------------------------------------------"
echo "        RESUMO DO DEPLOY GLOBAL"
echo "-------------------------------------------"
echo "Início:       $START_DATE"
echo "Fim:          $END_DATE"
echo "Tempo Total:  ${MINUTES}m ${SECONDS}s"
echo ""

echo "Status Backend:  $BACKEND_STATUS"
if [ "$BACKEND_STATUS" == "❌ FALHOU" ]; then
    # Pega as últimas 5 linhas para garantir que veremos o erro do Docker ou GCloud
    echo "  L Últimas mensagens do log:"
    tail -n 5 "$BACKEND_LOG" | sed 's/^/    /'
fi

echo ""
echo "Status Frontend: $FRONTEND_STATUS"
if [ "$FRONTEND_STATUS" == "❌ FALHOU" ]; then
    echo "  L Últimas mensagens do log:"
    tail -n 5 "$FRONTEND_LOG" | sed 's/^/    /'
fi
echo "-------------------------------------------"

# Opcional: Apagar logs apenas se deram sucesso, manter se falharam
# rm -f "$BACKEND_LOG" "$FRONTEND_LOG"

echo ""
