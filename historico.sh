#!/bin/bash
# Vuelca a LibreView el histórico de Nightscout por semanas (un POST por
# semana, ~1 MB; un mes entero se acerca a 4 MB y no sabemos el límite).
#
#   ./historico.sh 2023-04-17 2026-09-03
#
# Cloudflare limita el ritmo (HTTP 429 "error code: 1015"): a un envío cada 4 s
# cortó a las 13 semanas. De ahí los 30 s entre tramos y el reintento con 90 s
# de espera. Un tramo rechazado por el 1015 no llega a Abbott, así que repetirlo
# es seguro. Si un tramo falla 5 veces se para aquí: se relanza desde esa fecha.
#
# Idempotencia: el recordNumber es determinista (1+AAAAMMDDhhmmss), así que un
# tramo repetido no debería duplicarse, pero no lo hemos verificado en la web:
# NO repetir tramos ya subidos si no hace falta.
set -uo pipefail
cd "$(dirname "$0")"
[ $# -eq 2 ] || { echo "uso: $0 DESDE HASTA (YYYY-MM-DD)"; exit 1; }
desde=$1; fin=$2
echo $$ > state/historico.pid
while [[ "$desde" < "$fin" ]]; do
  hasta=$(date -d "$desde + 7 days" +%F); [[ "$hasta" > "$fin" ]] && hasta=$fin
  ok=0
  for intento in 1 2 3 4 5; do
    if salida=$(./subir-a-libreview.sh "$desde" "$hasta" 2>&1); then ok=1; break; fi
    echo "$(date -Is)  $desde -> $hasta  intento $intento falló: $(grep -oE 'error code: [0-9]+|ERROR.*' <<<"$salida" | head -1 | cut -c1-120) — espero 90 s" | tee -a logs/historico.log
    sleep 90
  done
  if [ $ok = 0 ]; then echo "$(date -Is)  $desde -> $hasta  ABANDONADO tras 5 intentos" | tee -a logs/historico.log; rm -f state/historico.pid; exit 1; fi
  echo "$(date -Is)  $desde -> $hasta  $(grep -E 'leído de nightscout|nada que subir' <<<"$salida" | head -1) | $(grep -oE '"status":[0-9]+' <<<"$salida" | head -1) | $(grep -oE 'ultimo=[^ ]+' <<<"$salida")" | tee -a logs/historico.log
  desde=$hasta; sleep 30
done
rm -f state/historico.pid
