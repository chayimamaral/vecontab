# Estágio 1: Build do Next.js
FROM node:20-alpine AS builder
# Instalando libc6-compat caso precise de alguma dependência nativa no Alpine
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .

ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL

RUN npm run build

# Estágio 2: Runner Node.js (Otimizado e Seguro)
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=8080
ENV HOSTNAME=0.0.0.0

# 1. Criar usuário e grupo para o Next.js (Segurança)
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# 2. Copiar apenas o necessário com as permissões corretas
COPY --from=builder /app/public ./public

# O Next.js cria automaticamente a pasta .next/standalone no build
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# 3. Mudar para o usuário sem privilégios
USER nextjs

EXPOSE 8080

# O server.js é gerado pelo build 'standalone' do Next.js
CMD ["node", "server.js"]