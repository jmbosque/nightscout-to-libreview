#!/bin/bash
# Sube un rango de datos de Nightscout a LibreView, para que el médico lo vea
# en la interfaz de Abbott a la que está acostumbrado.
#
#   ./subir-a-libreview.sh 2026-08-01 2026-09-01          # sube de verdad
#   DRY_RUN=true ./subir-a-libreview.sh 2026-08-01 2026-09-01   # sólo lee y enseña
#
# Ojo: LibreView no ofrece forma de borrar lo subido. Probar siempre antes con
# DRY_RUN y con un rango corto.
set -euo pipefail
cd "$(dirname "$0")"
[ $# -eq 2 ] || { echo "uso: $0 DESDE(YYYY-MM-DD) HASTA(YYYY-MM-DD)"; exit 1; }
set -a; source .env; set +a
mkdir -p state
red=(); [ -n "${DOCKER_NETWORK:-}" ] && red=(--network "$DOCKER_NETWORK")

docker run --rm "${red[@]}" \
  -v "$PWD":/app:ro \
  -v "$PWD/state":/state \
  -w /app \
  -e NS_URL -e NS_TOKEN -e LV_USER -e LV_PASS \
  -e FROM_DATE="$1" -e TO_DATE="$2" -e DRY_RUN="${DRY_RUN:-false}" \
  node:20-alpine node run.js
