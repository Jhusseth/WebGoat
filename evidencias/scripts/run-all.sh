#!/usr/bin/env bash
# Flujo completo de la actividad:
#   1. Compila WebGoat desde el proyecto montado.
#   2. Corre las 4 pruebas negativas con los controles activos (deben pasar).
#   3. Navega WebGoat a través del proxy ZAP y exporta las alertas del escaneo pasivo.
#   4. Repite las pruebas quitando un control a la vez (deben fallar) y revierte los parches.
#
# Todo queda en /resultados: logs, reportes de pruebas, reporte ZAP y resumen.txt.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/run-tests.sh
source "$HERE/run-tests.sh"

ZAP_URL="${ZAP_URL:-http://zap:8090}"
WEBGOAT_URL="${WEBGOAT_URL:-http://runner:8080/WebGoat}"
ESTADO="$RESULTS_DIR/estado.csv"
PARCHE_ACTIVO=""

limpiar() {
  detener_app
  if [ -n "$PARCHE_ACTIVO" ]; then
    revertir_parche "$PARCHE_ACTIVO" || true
    PARCHE_ACTIVO=""
  fi
  # El contenedor corre como root; devolvemos los artefactos al usuario del host.
  if [ "$(id -u)" = "0" ] && [ -n "${HOST_UID:-}" ]; then
    chown -R "${HOST_UID}:${HOST_GID:-$HOST_UID}" "$PROJECT_DIR/target" "$RESULTS_DIR" 2>/dev/null || true
  fi
}
trap limpiar EXIT

registrar() {
  printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$ESTADO"
}

esperar_zap() {
  log "Esperando a ZAP en $ZAP_URL ..."
  for _ in $(seq 1 90); do
    if curl -fsS -o /dev/null "$ZAP_URL/JSON/core/view/version"; then
      log "ZAP disponible."
      return 0
    fi
    sleep 2
  done
  log "ERROR: ZAP no respondió."
  return 1
}

generar_trafico() {
  log "Navegando WebGoat a través del proxy ZAP (Playwright)..."
  if ZAP_PROXY="$ZAP_URL" WEBGOAT_URL="$WEBGOAT_URL" \
      node /opt/trafico/zap-traffic.js >> "$LOGS_DIR/trafico.log" 2>&1; then
    log "Navegación completada."
    return 0
  fi
  log "La navegación con Playwright falló; usando el spider de ZAP como respaldo."
  local encoded
  encoded=$(printf '%s' "$WEBGOAT_URL/" | sed 's|:|%3A|g; s|/|%2F|g')
  curl -fsS "$ZAP_URL/JSON/spider/action/scan/?url=$encoded&maxChildren=5" >> "$LOGS_DIR/trafico.log" 2>&1 || true
}

esperar_escaneo_pasivo() {
  log "Esperando a que ZAP termine el escaneo pasivo..."
  local pendientes="?"
  for _ in $(seq 1 90); do
    pendientes=$(curl -fsS "$ZAP_URL/JSON/pscan/view/recordsToScan" 2>/dev/null |
      sed -n 's/.*"recordsToScan":"\{0,1\}\([0-9]*\)"\{0,1\}.*/\1/p')
    if [ "$pendientes" = "0" ]; then
      log "Escaneo pasivo completado."
      return 0
    fi
    sleep 2
  done
  log "Aviso: el escaneo pasivo no confirmó 0 pendientes (último valor: $pendientes)."
  return 0
}

exportar_reportes_zap() {
  log "Exportando alertas y reporte de ZAP..."
  local encoded
  encoded=$(printf '%s' "$WEBGOAT_URL" | sed 's|:|%3A|g; s|/|%2F|g')
  local total="0"
  for _ in $(seq 1 10); do
    curl -fsS "$ZAP_URL/JSON/core/view/alerts/?baseurl=$encoded" \
      -o "$RESULTS_DIR/reportes-zap/alertas.json" || true
    total=$(grep -o '"id":"[0-9]*"' "$RESULTS_DIR/reportes-zap/alertas.json" 2>/dev/null | wc -l)
    if [ "$total" -gt 0 ]; then
      break
    fi
    sleep 3
  done
  curl -fsS "$ZAP_URL/OTHER/core/other/jsonreport/" -o "$RESULTS_DIR/reportes-zap/reporte.json" || true
  curl -fsS "$ZAP_URL/OTHER/core/other/htmlreport/" -o "$RESULTS_DIR/reportes-zap/reporte.html" || true
  log "Alertas exportadas: $total"
}

# ── Ejecución ────────────────────────────────────────────────────────────────
preparar_entorno
: > "$ESTADO"

if [ ! -d "$PROJECT_DIR/.git" ]; then
  log "ERROR: no se encontró el proyecto en $PROJECT_DIR"
  exit 1
fi
if ! construir_app; then
  log "ERROR: falló la compilación de WebGoat."
  exit 1
fi

esperar_zap || true

log "========== RONDA 1: controles activos =========="
arrancar_app "$LOGS_DIR/app-ronda1.log" || exit 1
compilar_pruebas
ejecutar_pruebas "ronda1-controles-activos"
RC=$?
registrar "Ronda 1 - controles activos" "pasan" "$([ $RC -eq 0 ] && echo 'pasan' || echo 'fallan')"

generar_trafico
esperar_escaneo_pasivo
exportar_reportes_zap

detener_app

for CONTROL in autenticacion autorizacion validacion errores; do
  log "========== RONDA sin control: $CONTROL =========="
  if ! aplicar_parche "$CONTROL"; then
    log "ERROR: no se pudo aplicar el parche $CONTROL"
    registrar "Sin control: $CONTROL" "fallan" "error al aplicar parche"
    continue
  fi
  PARCHE_ACTIVO="$CONTROL"

  construir_app || true
  if arrancar_app "$LOGS_DIR/app-sin-$CONTROL.log"; then
    ejecutar_pruebas "sin-$CONTROL"
    RC=$?
    registrar "Sin control: $CONTROL" "fallan" "$([ $RC -eq 0 ] && echo 'pasan' || echo 'fallan')"
    detener_app
  else
    registrar "Sin control: $CONTROL" "fallan" "no arrancó"
  fi

  if revertir_parche "$CONTROL"; then
    PARCHE_ACTIVO=""
    log "Control $CONTROL restaurado."
  else
    log "ERROR: no se pudo revertir el parche $CONTROL"
  fi
done

# ── Resumen ──────────────────────────────────────────────────────────────────
{
  echo "RESUMEN DE LA EJECUCIÓN"
  echo
  echo "Generado: $(date '+%Y-%m-%d %H:%M:%S')"
  echo
  echo "Ronda | Esperado | Resultado"
  echo "------|----------|----------"
  while IFS='|' read -r ronda esperado obtenido; do
    [ -n "$ronda" ] && echo "$ronda | $esperado | $obtenido"
  done < "$ESTADO"
  echo
  echo
echo "ALERTAS DE ZAP"
  echo
  if [ -f "$RESULTS_DIR/reportes-zap/alertas.json" ]; then
    echo "Total: $(grep -o '"id":"[0-9]*"' "$RESULTS_DIR/reportes-zap/alertas.json" | wc -l) alertas."
    echo
    echo "Repeticiones | Riesgo | Alerta"
    echo "-------------|--------|-------"
    grep -o '"name":"[^"]*"' "$RESULTS_DIR/reportes-zap/alertas.json" |
      sed 's/"name":"//; s/"$//' |
      sort | uniq -c | sort -rn |
      while read -r veces nombre; do
        echo "$veces | - | $nombre"
      done
  else
    echo "No se generó alertas.json"
  fi
} > "$RESULTS_DIR/resumen.txt"

log "Proceso terminado. Revisa $RESULTS_DIR/resumen.txt"
if git -C "$PROJECT_DIR" diff --quiet -- src/main/java; then
  log "Código fuente sin cambios pendientes (parches revertidos)."
else
  log "ATENCIÓN: quedan cambios en src/main/java. Revisa 'git status'."
fi
