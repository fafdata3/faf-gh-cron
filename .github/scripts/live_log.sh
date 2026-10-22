#!/usr/bin/env bash
# Sube en bucle un log local a Supabase Storage (bucket `assets`) para poder
# seguirlo EN DIRECTO desde fuera del CI (GitHub no expone logs de runs en curso).
#
# Uso: live_log.sh <fichero_local> <ruta_remota> [intervalo_segundos]
#   fichero_local : p.ej. "$RUNNER_TEMP/live.log"
#   ruta_remota   : p.ej. "logs/probe-rfef-123456.log"
#
# Requiere SUPABASE_URL y SUPABASE_SERVICE_KEY en el entorno. Nunca falla el
# paso: los errores de subida se ignoran (es solo observabilidad).
set -u

FILE="${1:?falta el fichero local}"
REMOTE="${2:?falta la ruta remota}"
EVERY="${3:-12}"

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_SERVICE_KEY:-}" ]; then
  echo "[live] sin credenciales de Supabase: log en vivo desactivado" >&2
  exit 0
fi

URL="${SUPABASE_URL%/}/storage/v1/object/assets/${REMOTE}"
echo "[live] subiendo $FILE -> assets/$REMOTE cada ${EVERY}s" >&2

while true; do
  if [ -s "$FILE" ]; then
    if ! curl -sS -m 30 -X POST "$URL" \
        -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
        -H "x-upsert: true" \
        -H "Content-Type: text/plain; charset=utf-8" \
        --data-binary "@${FILE}" >/dev/null 2>&1; then
      echo "[live] fallo de subida (se reintenta)" >&2
    fi
  fi
  sleep "$EVERY"
done
