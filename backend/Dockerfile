# Estágio de Compilação
FROM golang:1.26.1-alpine AS builder

# Instala git e ferramentas de build essenciais
RUN apk add --no-cache git ca-certificates

WORKDIR /app

# Cache de dependências
COPY go.mod go.sum ./
RUN go mod download

# Copia o código fonte (considerando que o contexto do Docker é a pasta /backend)
COPY . .

# Compila o binário estático
# -ldflags="-w -s" remove tabelas de símbolos para diminuir o binário
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o vecontab-backend ./cmd/api/main.go

# Estágio de Execução
FROM alpine:latest

# Instala certificados para o TLS do Postgres e tzdata para o horário do Brasil
RUN apk --no-cache add ca-certificates tzdata

# Configura o fuso horário para Florianópolis/São Paulo
ENV TZ=America/Sao_Paulo

WORKDIR /root/

# Copia o binário do estágio anterior
COPY --from=builder /app/vecontab-backend .

# Porta padrão que o Cloud Run espera (ele injetará o valor em $PORT)
EXPOSE 8080

# Execução
CMD ["./vecontab-backend", "-port", "8080"]
