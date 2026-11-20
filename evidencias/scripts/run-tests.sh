#!/usr/bin/env bash
# Funciones compartidas: construir WebGoat, arrancarlo y ejecutar las pruebas negativas.
# Se puede usar de forma independiente (solo pruebas) o como base de run-all.sh.

PROJECT_DIR="${PROJECT_DIR:-/proyecto}"
RESULTS_DIR="${RESULTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/resultados}"
APP_PORT="${APP_PORT:-8080}"
BASE_URL="http://127.0.0.1:${APP_PORT}/WebGoat"
LOGS_DIR="$RESULTS_DIR/logs"
APP_PID=""
JAR=""

MVN=(
  ./mvnw -B -ntp
  -Dcheckstyle.skip=true
  -Dpmd.skip=true
  -Dspotless.check.skip=true
  -Dspotless.apply.skip=true
)

log() {
  local line
  line="[$(date '+%H:%M:%S')] $*"
  printf '%s\n' "$line" | tee -a "$RESULTS_DIR/log-general.txt"
}

preparar_entorno() {
  mkdir -p "$RESULTS_DIR"/{logs,tests,reportes-zap}
  : > "$RESULTS_DIR/log-general.txt"
  # El repositorio va montado desde el host; git avisa de propietario distinto.
  git config --global --add safe.directory "$PROJECT_DIR" 2>/dev/null || true
}

resolver_jar() {
  JAR=$(find "$PROJECT_DIR/target" -maxdepth 1 -name 'webgoat-*.jar' ! -name '*.original' | head -n 1)
  if [ -z "$JAR" ]; then
    log "ERROR: no se encontró el jar de WebGoat en $PROJECT_DIR/target"
    return 1
  fi
  log "Jar de WebGoat: $JAR"
}

construir_app() {
  log "Compilando WebGoat (sin pruebas)..."
  (
    cd "$PROJECT_DIR" &&
      "${MVN[@]}" -Dmaven.test.skip=true package
  ) >> "$LOGS_DIR/build.log" 2>&1
  local rc=$?
  resolver_jar || return 1
  return $rc
}

compilar_pruebas() {
  log "Compilando clases de prueba..."
  (
    cd "$PROJECT_DIR" &&
      "${MVN[@]}" -DskipTests -P'!start-server' test-compile
  ) >> "$LOGS_DIR/build.log" 2>&1
}

arrancar_app() {
  local logfile="$1"
  log "Arrancando WebGoat en el puerto $APP_PORT..."
  (
    cd "$PROJECT_DIR" &&
      exec java \
        -Dwebgoat.user.directory=/tmp/webgoat-evidencias \
        -Dwebgoat.server.directory=/tmp/webgoat-evidencias \
        -Dspring.main.banner-mode=off \
        --enable-native-access=ALL-UNNAMED \
        --add-opens java.base/java.lang=ALL-UNNAMED \
        --add-opens java.base/java.util=ALL-UNNAMED \
        --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
        --add-opens java.desktop/java.beans=ALL-UNNAMED \
        --add-opens java.base/sun.nio.ch=ALL-UNNAMED \
        --add-opens java.base/java.io=ALL-UNNAMED \
        -jar "$JAR" \
        --server.address=0.0.0.0 \
        --server.port="$APP_PORT"
  ) > "$logfile" 2>&1 &
  APP_PID=$!

  for _ in $(seq 1 90); do
    if curl -fsS -o /dev/null "$BASE_URL/login"; then
      log "WebGoat listo (PID $APP_PID)."
      return 0
    fi
    if ! kill -0 "$APP_PID" 2>/dev/null; then
      log "ERROR: WebGoat terminó durante el arranque. Ver $logfile"
      return 1
    fi
    sleep 2
  done
  log "ERROR: WebGoat no respondió a tiempo. Ver $logfile"
  return 1
}

detener_app() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    log "Deteniendo WebGoat (PID $APP_PID)..."
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  APP_PID=""
}

# Ejecuta la clase NegativeSecurityIntegrationTest contra la instancia en marcha.
# Devuelve 0 si todas las pruebas pasan y distinto de 0 si alguna falla.
ejecutar_pruebas() {
  local etiqueta="$1"
  local logfile="$LOGS_DIR/pruebas-$etiqueta.log"
  log "Ejecutando pruebas negativas ($etiqueta)..."
  (
    cd "$PROJECT_DIR" &&
      "${MVN[@]}" \
        -P'!start-server' \
        -Dwebgoat.port="$APP_PORT" \
        -Dwebgoat.context=WebGoat \
        -Dit.test=NegativeSecurityIntegrationTest \
        -DfailIfNoTests=false \
        failsafe:integration-test failsafe:verify
  ) > "$logfile" 2>&1
  local rc=$?
  mkdir -p "$RESULTS_DIR/tests/$etiqueta"
  cp "$PROJECT_DIR"/target/failsafe-reports/*.txt "$RESULTS_DIR/tests/$etiqueta/" 2>/dev/null || true
  if [ $rc -eq 0 ]; then
    log "Resultado $etiqueta: TODAS LAS PRUEBAS PASAN"
  else
    log "Resultado $etiqueta: HAY PRUEBAS QUE FALLAN (esperado al quitar un control)"
  fi
  return $rc
}

aplicar_parche() {
  local nombre="$1"
  log "Quitando control: $nombre"
  git -C "$PROJECT_DIR" apply "$(dirname "${BASH_SOURCE[0]}")/patches/$nombre.patch"
}

revertir_parche() {
  local nombre="$1"
  git -C "$PROJECT_DIR" apply -R "$(dirname "${BASH_SOURCE[0]}")/patches/$nombre.patch"
}
