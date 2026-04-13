stop:
	@echo "Finalizando processos do VContab..."
	@pkill -f "go run cmd/api/main.go" || true
	@pkill -f "next-dev" || true
	@pkill -f "node" || true