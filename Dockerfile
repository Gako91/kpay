# Multi-stage Dockerfile pour KPay (Haute Performance Vlang)
FROM thevlang/vlang:alpine-dev AS builder

WORKDIR /build

# Dépendances système de build
RUN apk add --no-cache gcc musl-dev postgresql-dev

# Copie des fichiers sources du projet
COPY . .

# Compilation du binaire de production optimisé avec GCC
RUN v -cc gcc -prod -o /build/kpay main.v

# Image d'exécution finale légère
FROM alpine:3.19

WORKDIR /app

# Dépendances runtime (libc, libpq PostgreSQL)
RUN apk add --no-cache libpq ca-certificates tzdata \
    && mkdir -p /app/storage/payslips

# Copie du binaire compilé et des fichiers nécessaires
COPY --from=builder /build/kpay /app/kpay
COPY --from=builder /build/migrations /app/migrations

# Port d'écoute par défaut
EXPOSE 8089

# Exécution du binaire KPay
CMD ["/app/kpay"]
