# Cómo validar las evidencias

Esta es la lista que usaría yo para revisar la entrega. Con `resultados/` generado tras
`docker compose up --build`, todo se comprueba desde la terminal.

## 1. La ronda con controles pasa

```bash
grep -E "Tests run:|BUILD" resultados/logs/pruebas-ronda1-controles-activos.log
```

Debe aparecer `Tests run: 4, Failures: 0, Errors: 0, Skipped: 0` y `BUILD SUCCESS`.
En `resultados/tests/ronda1-controles-activos/` está el reporte de Failsafe como
respaldo.

## 2. Cada ronda sin control falla

```bash
cat resultados/resumen.txt
```

La tabla debe verse así:

|            Ronda            | Esperado | Resultado |
|-----------------------------|----------|-----------|
| Ronda 1 - controles activos | pasan    | pasan     |
| Sin control: autenticacion  | fallan   | fallan    |
| Sin control: autorizacion   | fallan   | fallan    |
| Sin control: validacion     | fallan   | fallan    |
| Sin control: errores        | fallan   | fallan    |

Para ver qué prueba falló en cada ronda:

```bash
grep -E "Tests run:|FAILURE!|<<<" resultados/logs/pruebas-sin-*.log
```

Lo importante es que en cada log falle solo la prueba del control eliminado:

- `sin-autenticacion` → falla `unauthenticatedRequestToReportCardIsRejected`
- `sin-autorizacion` → falla `regularUserCannotAccessAdminEndpoints`
- `sin-validacion` → falla `registrationWithMismatchedPasswordsIsRejected`
- `sin-errores` → falla `unknownAdminResourceReturnsNotFoundWithoutLeakingInternals`

## 3. El código quedó limpio

Al final de `resultados/log-general.txt` debe decir:

```
Código fuente sin cambios pendientes (parches revertidos).
```

También puedes confirmarlo a mano:

```bash
git status --short src/main/java
```

No debe listar nada.

## 4. El reporte de ZAP existe y tiene alertas

```bash
ls -lh resultados/reportes-zap/
```

Deben estar `alertas.json`, `reporte.json` y `reporte.html`. Para abrir el reporte visual:

```bash
xdg-open resultados/reportes-zap/reporte.html   # Linux
open resultados/reportes-zap/reporte.html       # macOS
```

Cuenta de alertas:

```bash
grep -o '"id":"[0-9]*"' resultados/reportes-zap/alertas.json | wc -l
```

En mi ejecución salieron 139 alertas. La mayoría son de riesgo bajo o informativo.

Si quieres ver el detalle de las tres alertas que analicé, está en
`03-reporte-zap.md`, con su riesgo, la evidencia y la corrección propuesta.

## 5. Trazabilidad del tráfico

```bash
cat resultados/logs/trafico.log
```

Ahí se ve la navegación que hizo Playwright a través del proxy: login, bienvenida,
lecciones, buzón, registro y el intento a `/service/admin/users` con un usuario normal.
Ese tráfico es el que analizó el escáner pasivo de ZAP.

## Nota sobre reproducibilidad

El escaneo pasivo de ZAP no siempre produce exactamente las mismas alertas: depende de
las versiones de la imagen y de las reglas del día. Las tres alertas documentadas son las
que salieron en mi ejecución. Si en una repetición aparece alguna distinta, el método
para analizarla es el mismo: mirar el riesgo, abrir la evidencia (petición y respuesta) y
proponer la corrección.
