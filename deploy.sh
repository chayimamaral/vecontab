#!/bin/bash

# Removemos o 'set -e' para que o script não pare no meio em caso de erro
set +e

START_TIME=$(date +%s)
START_DATE=$(date +"%H:%M:%S")

# Arquivos temporários para capturar apenas os erros (stderr)
BACKEND_LOG=$(mktemp)
FRONTEND_LOG=$(mktemp)

echo ""
echo "--- Iniciando Deploy Global [Início: $START_DATE] ---"
echo ""

# --- Executa backend ---
echo "📦 Processando Backend..."
# Redireciona apenas o erro (2>) para o log, mas mantém a saída no terminal (tee)
if (cd backend && ./deploy-backend.sh 2> "$BACKEND_LOG"); then
    BACKEND_STATUS="✅ Sucesso"
else
    BACKEND_STATUS="❌ FALHOU"
fi

echo ""

# --- Executa frontend ---
echo "🎨 Processando Frontend..."
if (cd frontend && ./deploy-frontend.sh 2> "$FRONTEND_LOG"); then
    FRONTEND_STATUS="✅ Sucesso"
else
    FRONTEND_STATUS="❌ FALHOU"
fi

echo ""

# Captura o horário de fim
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
    echo "  L Erro detectado: $(cat "$BACKEND_LOG" | tail -n 2)"
fi

echo "Status Frontend: $FRONTEND_STATUS"
if [ "$FRONTEND_STATUS" == "❌ FALHOU" ]; then
    echo "  L Erro detectado: $(cat "$FRONTEND_LOG" | tail -n 2)"
fi
echo "-------------------------------------------"

# Limpeza dos arquivos temporários
rm -f "$BACKEND_LOG" "$FRONTEND_LOG"

echo ""