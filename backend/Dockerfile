# Multi-stage Dockerfile pour KPay — autonome (aucune dépendance au poste de dev)
# --- Stage 1 : Build ---
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc make libc6-dev libpq-dev libatomic1 git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Compilation de la dernière version de V depuis les sources officielles
RUN git clone --depth 1 https://github.com/vlang/v /opt/vlang \
    && cd /opt/vlang \
    && make \
    && ./v symlink \
    && v version

# Module externe pdf
RUN v install pdf

WORKDIR /build
COPY . .

RUN v -cc gcc -prod -o /build/kpay main.v

# --- Stage 2 : Runtime (Debian glibc, compatible libpq) ---
FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 libatomic1 ca-certificates tzdata \
    && mkdir -p /app/storage/payslips \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/kpay /app/kpay
COPY --from=builder /build/migrations /app/migrations
COPY --from=builder /build/openapi.yaml /app/openapi.yaml

EXPOSE 9199

CMD ["/app/kpay"]
