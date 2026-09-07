#!/bin/bash
# Sube a LibreView lo nuevo desde la última sincronización. Lo lanza cron.
# La marca (último timestamp subido) vive en state/ultimo.txt.
#
# Avisa por correo (MAIL_TO/MAIL_FROM/MAIL_CMD en .env) sólo cuando algo va mal:
#   ❌ el envío falla (Nightscout caído, login de LibreView, Cloudflare 1015…)
#   ⚠️ termina bien pero no había NADA nuevo: xDrip no está subiendo a Nightscout
# Si todo va bien, silencio y una línea en logs/sync.log.
#
# Además hace ping a healthchecks.io (HC_PING_URL en .env): /start al empezar,
# OK al acabar con datos, /fail si falla o si no había lecturas nuevas. Si el
# cron NO llega a ejecutarse (Pi apagada, cron roto), healthchecks avisa solo:
# es el latido externo que un script no puede darse a sí mismo.
set -uo pipefail
cd "$(dirname "$0")"
set -a; source .env; set +a          # MAIL_TO, MAIL_FROM, MAIL_CMD, HC_PING_URL (todo opcional)
MAIL_CMD="${MAIL_CMD:-sudo msmtp -a default}"; HC="${HC_PING_URL:-}"
hc() {   # $1 = "" | start | fail ; cuerpo por stdin (se guarda en el log del ping)
  [ -n "$HC" ] || return 0
  curl -fsS -m 10 --retry 5 -o /dev/null --data-binary @- "$HC${1:+/$1}" 2>/dev/null \
    || echo "$(date -Is) aviso: no se pudo notificar a healthchecks (${1:-ok})" >> logs/sync.log
}
avisar() {   # $1 = asunto; cuerpo por stdin. Sin MAIL_TO no hace nada.
  [ -n "${MAIL_TO:-}" ] || return 0
  { echo "To: $MAIL_TO"; echo "From: ${MAIL_FROM:-$MAIL_TO}"; echo "Subject: $1"
    echo "Content-Type: text/plain; charset=UTF-8"; echo; cat
    echo; echo "--"; echo "Script: $PWD/sync-diario.sh · log: $PWD/logs/sync.log"
  } | $MAIL_CMD "$MAIL_TO"
}
hoy=$(date +%d/%m)
hc start </dev/null

desde=$(cat state/ultimo.txt 2>/dev/null) || {
  echo "No existe state/ultimo.txt: no sé desde cuándo subir." | avisar "❌ LibreView sync $hoy: falta la marca"
  hc fail <<<"falta state/ultimo.txt"
  exit 1; }
hasta=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if ! salida=$(./subir-a-libreview.sh "$desde" "$hasta" 2>&1); then
  echo "$(date -Is) ERROR $desde -> $hasta | $(tail -c 300 <<<"$salida" | tr '\n' ' ')" >> logs/sync.log
  { echo "La sincronización Nightscout → LibreView ha FALLADO."; echo
    echo "Tramo: $desde -> $hasta"; echo; echo "Últimas líneas:"
    grep -vE 'entries url' <<<"$salida" | tail -n 12
  } | avisar "❌ LibreView sync $hoy: FALLÓ"
  hc fail <<<"FALLÓ $desde -> $hasta: $(grep -vE 'entries url' <<<"$salida" | tail -n 5)"
  exit 1
fi

ultimo=$(sed -n 's/.*ultimo=\([^ ]*\).*/\1/p' <<<"$salida")
n=$(grep -oE 'glucosa [0-9]+' <<<"$salida" | grep -oE '[0-9]+' || echo 0)
[ -n "$ultimo" ] && echo "$ultimo" > state/ultimo.txt
echo "$(date -Is) $desde -> ${ultimo:-sin datos nuevos} | lecturas $n" >> logs/sync.log

if [ "${n:-0}" -eq 0 ]; then
  { echo "El envío a LibreView ha ido bien, pero Nightscout no tenía NINGUNA lectura nueva"
    echo "desde $desde. Lo más probable: xDrip4iOS no está subiendo a Nightscout."; echo
    echo "Comprueba xDrip (Configuración → Nightscout) y https://diabetes.suiteanna.es"
  } | avisar "⚠️ LibreView sync $hoy: sin lecturas nuevas"
  hc fail <<<"sin lecturas nuevas en Nightscout desde $desde (¿xDrip no sube?)"
else
  hc <<<"OK: $n lecturas, $desde -> $ultimo"
fi
