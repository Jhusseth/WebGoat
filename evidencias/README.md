# Actividad: pruebas negativas y análisis pasivo con ZAP

Este directorio reúne todo lo que usé para la actividad del curso: las cuatro pruebas
negativas contra WebGoat, la forma de comprobar que de verdad detectan la ausencia de cada
control, y el análisis pasivo hecho con ZAP navegando la aplicación a través del proxy.

La idea fue no depender de mi máquina para reproducirlo. Con Docker levantado, un solo
comando construye el proyecto, ejecuta todo y deja las evidencias en `resultados/`. Si el
profesor quiere verlo desde cero, no necesita instalar Maven, Java ni ZAP.

## Contenido

|          Archivo           |                              Para qué sirve                              |
|----------------------------|--------------------------------------------------------------------------|
| `docker-compose.yml`       | Levanta ZAP en el puerto 8090 y el contenedor que ejecuta todo el flujo. |
| `Dockerfile.runner`        | Imagen con JDK 25, Maven Wrapper, git y Playwright.                      |
| `scripts/run-all.sh`       | Orquestador: compila, prueba, navega, escanea y resume.                  |
| `scripts/run-tests.sh`     | Funciones de compilación, arranque y ejecución de las pruebas.           |
| `scripts/zap-traffic.js`   | Navegación real con Chromium a través del proxy de ZAP.                  |
| `scripts/patches/*.patch`  | Parches que quitan un control a la vez para la comprobación inversa.     |
| `01-guia-ejecucion.md`     | Cómo correr todo, qué esperar y cuánto tarda.                            |
| `02-nota-pruebas.md`       | Qué control verifica cada prueba y por qué elegí esos endpoints.         |
| `03-reporte-zap.md`        | Reporte de ZAP y mis notas de las tres alertas elegidas.                 |
| `04-validar-evidencias.md` | Lista de verificación para revisar los resultados.                       |

## Ejecución rápida

```bash
cd evidencias
docker compose up --build
```

Al terminar, los resultados quedan en `resultados/`:

- `resumen.txt`: tabla con el resultado de cada ronda.
- `logs/pruebas-*.log`: salida de Maven/Failsafe de cada ronda.
- `tests/`: reportes de Surefire/Failsafe copiados por ronda.
- `reportes-zap/`: alertas en JSON y reporte HTML de ZAP.

## Commit de las pruebas

Las pruebas viven en `src/it/java/org/owasp/webgoat/integration/NegativeSecurityIntegrationTest.java`.
El commit de esta entrega es `cbb4dbf` (`test: add negative security tests and evidence bundle`).
