# Multi-stage Dockerfile pour KPay (Haute Performance Vlang)
# Construction de V depuis le repository officiel pour garantir la version la plus récente (avec json2 et vpm)
FROM alpine:3.20 AS builder

WORKDIR /build

# Dépendances système pour compiler V et le projet
RUN apk add --no-cache git make gcc musl-dev postgresql-dev

# Installation de la version à jour de Vlang
RUN git clone --depth 1 https://github.com/vlang/v /opt/vlang \
    && cd /opt/vlang \
    && make \
    && ./v symlink

# Installation du module externe pdf via v install
RUN v install pdf

# Copie des fichiers sources du projet
COPY . .

# Compilation du binaire de production optimisé avec GCC
RUN v -enable-globals -cc gcc -prod -o /build/kpay main.v

# Image d'exécution finale ultra-légère
FROM alpine:3.20

WORKDIR /app

# Dépendances runtime (libc, libpq PostgreSQL)
RUN apk add --no-cache libpq ca-certificates tzdata \
    && mkdir -p /app/storage/payslips

# Copie du binaire compilé et des fichiers nécessaires
COPY --from=builder /build/kpay /app/kpay
COPY --from=builder /build/migrations /app/migrations
COPY --from=builder /build/openapi.yaml /app/openapi.yaml

# Port d'écoute par défaut
EXPOSE 9199

# Exécution du binaire KPay
CMD ["/app/kpay"]
