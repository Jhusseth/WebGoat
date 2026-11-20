#!/usr/bin/env bash
# Atajo para lanzar la actividad completa con un solo comando.
# Levanta ZAP y el contenedor de ejecución, y apaga todo cuando el runner termina.
set -uo pipefail
cd "$(dirname "$0")"

docker compose up --build --abort-on-container-exit --exit-code-from runner
CODIGO=$?
docker compose down --remove-orphans
exit $CODIGO
