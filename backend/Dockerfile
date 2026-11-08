# Multi-stage Dockerfile pour KPay
# --- Stage 1 : Build ---
# V 0.5.2 (commit 1ac8043, épinglé — cf. compose.yml context 'vlang' : /home/gnoboa/kpay-v)
# est copié depuis l'environnement local (contexte 'vlang') au lieu d'être bootstrappé
# dans le conteneur (bootstrap incompatible gcc récent).
FROM debian:bookworm-slim AS builder

WORKDIR /build

# Dépendances système pour compiler l'application avec V + GCC
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc libc6-dev libpq-dev git ca-certificates
# libatomic : dépendance runtime du binaire V local
RUN apt-get install -y --no-install-recommends libatomic1

# Copie du compilateur V local (binaire + vlib) au MÊME chemin absolu que sur le host
# (le binaire embauche /home/gnoboa/kpay-v/vlib/... pour ses fichiers pré-compilés)
# La toolchain est épinglée au commit 1ac8043 (V 0.5.2, 13/09/2026) : le commit plus récent
# 94a3a56 (16/09/2026) régresse le codegen -prod (panic "option/result propagation failed").
RUN mkdir -p /home/gnoboa/kpay-v
COPY --from=vlang /v /home/gnoboa/kpay-v/v
COPY --from=vlang /v1_fallback /home/gnoboa/kpay-v/v1_fallback
COPY --from=vlang /vlib /home/gnoboa/kpay-v/vlib
COPY --from=vlang /thirdparty /home/gnoboa/kpay-v/thirdparty
COPY --from=vlang /cmd /home/gnoboa/kpay-v/cmd
COPY --from=vlang /vc /home/gnoboa/kpay-v/vc
COPY --from=vlang /v.mod /home/gnoboa/kpay-v/v.mod
ENV PATH="/home/gnoboa/kpay-v:${PATH}"

RUN v version

# Module externe pdf : copié depuis l'installation locale (vpm pré-compilé du host = GLIBC 2.38)
RUN mkdir -p /root/.vmodules
COPY --from=vmodules /pdf /root/.vmodules/pdf

# Copie des fichiers sources du projet
COPY . .

# Compilation du binaire de production optimisé avec GCC
# Attention : -prod SANS -g déclenche un bug de codegen V (panic "option/result propagation
# propagation failed" au démarrage). Le -g est indispensable jusqu'au correctif upstream.
RUN v -cc gcc -prod -g -o /build/kpay main.v

# --- Stage 2 : Runtime (Debian glibc, compatible binaire PostgreSQL) ---
FROM debian:bookworm-slim

WORKDIR /app

# Dépendances runtime (libpq, certs, fuseau, libatomic pour V)
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 libatomic1 ca-certificates tzdata \
    && mkdir -p /app/storage/payslips \
    && rm -rf /var/lib/apt/lists/*

# Copie du binaire compilé et des fichiers nécessaires
COPY --from=builder /build/kpay /app/kpay
COPY --from=builder /build/migrations /app/migrations
COPY --from=builder /build/openapi.yaml /app/openapi.yaml

# Port d'écoute par défaut
EXPOSE 9199

# Exécution du binaire KPay
CMD ["/app/kpay"]
