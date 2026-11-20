# Reporte de ZAP y notas de las tres alertas

## Cómo hice el escaneo

Usé ZAP en modo daemon dentro de Docker, escuchando como proxy en el puerto **8090**.
El 8080 lo dejé para WebGoat, que es justo el detalle que pide el enunciado: si ZAP y
WebGoat comparten puerto, el proxy no arranca o se pisa con la aplicación.

El tráfico no lo generé con el spider de ZAP, sino con un navegador real. El script
`scripts/zap-traffic.js` abre Chromium con el proxy apuntando a ZAP, inicia sesión como
`webgoat-user`, recorre la bienvenida, el listado de lecciones, el buzón, el formulario de
registro, dos lecciones y un intento a `/service/admin/users`. El escáner pasivo de ZAP
analiza exactamente lo que ve el navegador en ese recorrido.

El resultado quedó en:

- `resultados/reportes-zap/reporte.html`: reporte visual de ZAP.
- `resultados/reportes-zap/reporte.json`: reporte en JSON.
- `resultados/reportes-zap/alertas.json`: alertas crudas, que es lo que usé para las notas.

La ejecución dejó **139 alertas**: 1 de riesgo alto, 40 medias, 49 bajas y 49 informativas.
Elegí tres que representan problemas distintos y que un cliente entendería rápido.

| Riesgo |                    Alerta                    |              Dónde aparece               |
|--------|----------------------------------------------|------------------------------------------|
| Medio  | Absence of Anti-CSRF Tokens                  | Formulario de registro (`/register.mvc`) |
| Medio  | Content Security Policy (CSP) Header Not Set | `/login` y el resto de páginas           |
| Alto   | Vulnerable JS Library (underscore 1.10.2)    | `/js/libs/underscore-min.js`             |

## Alerta 1: ausencia de tokens anti-CSRF

**Riesgo:** Medio (confianza baja según ZAP).
**CWE:** 352 (Cross-Site Request Forgery).

**Evidencia.** ZAP marcó el formulario de registro:

```
POST http://runner:8080/WebGoat/register.mvc
<form class="form-horizontal" action="/WebGoat/register.mvc" method='POST'>
No known Anti-CSRF token [anticsrf, CSRFToken, __RequestVerificationToken, ...] was found
```

Ningún formulario de la aplicación lleva un token oculto, y las peticiones que cambian
estado (registro, envío de correo, respuestas de lecciones) se aceptan solo con la cookie
de sesión.

**Por qué ocurre.** En `WebSecurityConfig` la aplicación desactiva CSRF a propósito
(`csrf.disable()`) porque varias lecciones enseñan precisamente ataques CSRF y necesitan
que la protección no interfiera. En un cliente real eso no se hace.

**Cómo lo corregiría.** Activar CSRF de Spring Security y usar
`CookieCsrfTokenRepository.withHttpOnlyFalse()` para que las páginas con JavaScript
puedan enviar el token en la cabecera `X-XSRF-TOKEN`. Excluiría del filtro solo las rutas
de las lecciones que dependen de ser vulnerables, y dejaría protegido todo el contenedor
(registro, administración, buzón, servicios). Como refuerzo, la cookie de sesión debería
salir con `SameSite=Lax` o `Strict`; ZAP también marcó `Cookie without SameSite Attribute`
en `/login`.

## Alerta 2: falta la cabecera Content-Security-Policy

**Riesgo:** Medio (confianza alta).
**CWE:** 693 (Protection Mechanism Failure).

**Evidencia.** En la respuesta de `/WebGoat/login` no aparece ninguna cabecera
`Content-Security-Policy`. ZAP lo reporta así:

```
GET http://runner:8080/WebGoat/login
Content Security Policy (CSP) Header Not Set
```

Lo mismo pasa con `X-Content-Type-Options` (48 respuestas) y `X-Frame-Options`
(8 páginas, incluida la de registro), que son las otras dos alertas de cabeceras.

**Por qué ocurre.** La configuración de seguridad desactiva por completo las cabeceras
por defecto de Spring Security (`headers.disable()`), otra decisión heredada de las
lecciones que necesitan poder mostrarse dentro de marcos o con contenido incrustado.

**Cómo lo corregiría.** Definir una política CSP razonable para el contenedor, por
ejemplo `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline';
img-src 'self' data:; frame-ancestors 'none'`, y volver a activar
`X-Content-Type-Options: nosniff` y `X-Frame-Options: DENY` con
`headers.contentTypeOptions()` y `headers.frameOptions()`. Igual que con CSRF, dejaría
las excepciones acotadas a las lecciones que las necesitan.

## Alerta 3: librería JavaScript vulnerable (underscore 1.10.2)

**Riesgo:** Alto (confianza media).
**CWE:** 1395 (Dependency on Vulnerable Third-Party Component).

**Evidencia.** ZAP identificó la versión en el propio archivo:

```
GET http://runner:8080/WebGoat/js/libs/underscore-min.js
//     Underscore.js 1.10.2
The identified library underscore.js, version 1.10.2 is vulnerable.
CVE-2021-23358, CVE-2026-27601
```

En el mismo barrido aparecieron otras cuatro librerías desactualizadas, todas de riesgo
medio: jQuery UI 1.12.1 (CVE-2021-41184, CVE-2021-41183, CVE-2021-41182, CVE-2022-31160),
Bootstrap 3.1.1, jQuery 2.1.4 y jQuery 3.4.1.

**Por qué ocurre.** WebGoat fija versiones antiguas de estas librerías porque algunas
lecciones dependen de sus comportamientos y de los CVEs asociados. En el proyecto hay una
regla explícita de no actualizar dependencias marcadas como necesarias para las lecciones,
así que aquí no las cambiaría.

**Cómo lo corregiría.** En un cliente real actualizaría underscore a la última rama 1.13
(la corrección de CVE-2021-23358 llegó en 1.12.1), jQuery a 3.5 o superior, jQuery UI a
1.13.2 o superior y Bootstrap a 3.4.1 o superior, y añadiría un análisis de composición
de dependencias en el pipeline (por ejemplo OWASP Dependency-Check o Dependabot) para
detectar estos casos antes de desplegar. En WebGoat la corrección sería aislar estas
librerías solo en las páginas de lecciones en lugar de servirlas globalmente.

## Cómo reproducir el reporte a mano (con la interfaz de ZAP)

Por si se quiere ver el escaneo en vivo, así lo haría sin Docker para ZAP:

1. Abrir ZAP y en **Options > Network > Local Servers/Proxies** cambiar el puerto del
   proxy de 8080 a **8090** (WebGoat se queda en el 8080).
2. Configurar el navegador para usar el proxy `127.0.0.1:8090` en HTTP y HTTPS.
3. Con WebGoat ya arrancado (`./mvnw spring-boot:run` en la raíz del proyecto), navegar
   por la aplicación: login con `webgoat-user` / `webgoat`, bienvenida, lecciones, buzón y
   registro.
4. En ZAP abrir la pestaña **Alerts** para revisar el escaneo pasivo.
5. Generar el reporte con **Report > Generate HTML Report** y guardarlo.

El flujo automatizado hace lo mismo, pero sin intervención manual: el navegador lo mueve
Playwright y las alertas se exportan por la API de ZAP a `resultados/reportes-zap/`.
