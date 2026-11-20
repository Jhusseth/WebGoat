# Guía de ejecución

## Lo que necesitas

Solo Docker con Compose. En mi máquina lo corrí con Docker 29 y Compose v5.6, pero
cualquier versión reciente sirve. La primera vez descarga dependencias de Maven y el
navegador de Playwright, así que hay que tener paciencia y conexión a internet.

No hace falta tener Java, Maven ni ZAP instalados: todo va dentro de los contenedores.

## Pasos

1. Abre una terminal en la carpeta `evidencias`:

   ```bash
   cd evidencias
   ```
2. Levanta el flujo completo:

   ```bash
   ./ejecutar.sh
   ```

   Ese script hace `docker compose up --build` y apaga ZAP cuando el runner termina,
   para que no quede nada corriendo. Si prefieres hacerlo a mano, el comando equivalente
   es `docker compose up --build --abort-on-container-exit --exit-code-from runner`.

3. Espera. El proceso hace esto, en orden:

   - compila WebGoat desde la carpeta del proyecto (`..`, montada como `/proyecto`);
   - arranca ZAP en modo daemon en el puerto **8090** (el 8080 lo usa WebGoat);
   - arranca WebGoat y corre las cuatro pruebas negativas (deben pasar todas);
   - abre un Chromium a través del proxy de ZAP y navega login, bienvenida, lecciones,
     buzón, registro y el endpoint de administración;
   - espera a que termine el escaneo pasivo y exporta las alertas;
   - repite las pruebas cuatro veces, quitando un control distinto en cada ronda
     (autenticación, autorización, validación y manejo de errores), y en cada una
     comprueba que la prueba correspondiente falle;
   - restaura el código automáticamente al terminar cada ronda.
4. Cuando termine, revisa:

   ```bash
   cat resultados/resumen.txt
   ```

   La tabla de `resumen.txt` debe mostrar "pasan" en la ronda 1 y "fallan" en las cuatro
   rondas sin control.

## Cuánto tarda

La primera ejecución tarda entre 10 y 20 minutos, casi todo por las descargas iniciales.
Las siguientes son más rápidas porque la caché de Maven queda en un volumen y la imagen
de Playwright ya está construida.

## Detalles que me parecieron importantes

- **Puertos.** ZAP escucha en 8090 porque WebGoat ocupa el 8080, igual que en el
  enunciado. Además dejo publicado el 8080 del contenedor para poder abrir WebGoat en el
  navegador mientras corre.
- **Los parches nunca se quedan aplicados.** `run-all.sh` revierte cada parche con
  `git apply -R` y al final comprueba que `src/main/java` no tenga cambios pendientes.
  Si algo se interrumpe, el `trap` de salida detiene la aplicación y revierte el parche
  activo.
- **Datos de WebGoat.** Uso un directorio temporal dentro del contenedor
  (`/tmp/webgoat-evidencias`) para no ensuciar el proyecto.
- **Si quieres correr solo las pruebas** con una instancia ya levantada, puedes usar las
  funciones de `scripts/run-tests.sh`, pero el flujo pensado para la entrega es el de
  `docker compose up`.

