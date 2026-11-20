# Nota de las pruebas: qué control verifica cada una

Aclaro algo primero: WebGoat es una aplicación deliberadamente vulnerable. Las lecciones
están hechas para que se puedan explotar y no las toqué. Lo que probé es el código del
contenedor (usuarios, sesión, administración y registro), que sí debe estar protegido
porque no forma parte del ejercicio de hacking.

Las cuatro pruebas están en
`src/it/java/org/owasp/webgoat/integration/NegativeSecurityIntegrationTest.java` y se
ejecutan con el perfil de pruebas de integración del proyecto (Failsafe + REST Assured).

## Resumen

| # |                            Prueba                            |  Control que verifica  |                                        Petición                                        |                     Resultado esperado                      |
|---|--------------------------------------------------------------|------------------------|----------------------------------------------------------------------------------------|-------------------------------------------------------------|
| 1 | `unauthenticatedRequestToReportCardIsRejected`               | Autenticación          | `GET /WebGoat/service/reportcard.mvc` sin cookie de sesión                             | Redirección 302 a `/login`, sin datos del reporte           |
| 2 | `regularUserCannotAccessAdminEndpoints`                      | Autorización           | `GET /WebGoat/service/admin/users` con sesión de `webgoat-user`                        | 403 Forbidden                                               |
| 3 | `registrationWithMismatchedPasswordsIsRejected`              | Validación de entradas | `POST /WebGoat/register.mvc` con `password` y `matchingPassword` distintos             | 200 con el formulario otra vez y el usuario no queda creado |
| 4 | `unknownAdminResourceReturnsNotFoundWithoutLeakingInternals` | Manejo de errores      | `GET /WebGoat/service/admin/users/{usuario-inexistente}` con sesión de `webgoat-admin` | 404 sin trazas ni clases internas en el cuerpo              |

## Por qué elegí cada endpoint

**Autenticación, `reportcard.mvc`.** Es un endpoint de servicio que devuelve datos del
usuario actual. Si se consulta sin sesión, no hay razón para servir nada. Me gustó porque
es un `GET` sencillo y el fallo se nota de inmediato: o redirige al login o filtra el
progreso de alguien.

**Autorización, `service/admin/users`.** El endpoint de administración lista todos los
usuarios y su progreso. Está protegido en dos capas: la regla de URL en
`WebSecurityConfig` (`hasAuthority("WEBGOAT_ADMIN")`) y los `@PreAuthorize` del
controlador. La prueba usa el usuario normal `webgoat-user`, que existe por defecto, y
espera un 403. Para la comprobación inversa hay que quitar las dos capas, porque con una
sola el acceso sigue bloqueado. Eso lo dejé documentado en el parche de autorización.

**Validación, `register.mvc`.** El formulario de registro valida tamaño y formato con
Bean Validation, y además `UserValidator` comprueba que las dos contraseñas coincidan.
Envié una petición con contraseñas distintas y verifico dos cosas: que el formulario se
vuelve a mostrar y que después no se puede iniciar sesión con ese usuario. Así no me
quedo solo con el código HTTP, también compruebo que el usuario no se creó.

**Manejo de errores, `service/admin/users/{username}`.** Pedí el detalle de un usuario
que no existe. Lo correcto es un 404 controlado y un cuerpo sin información interna.
La prueba falla si aparece una excepción, una clase de Spring o una traza en la
respuesta.

## Los parches de la comprobación inversa

En `scripts/patches/` hay un parche por control. Cada uno quita exactamente lo necesario:

|        Parche         |                                        Qué cambia                                         |                  Por qué                   |
|-----------------------|-------------------------------------------------------------------------------------------|--------------------------------------------|
| `autenticacion.patch` | `.anyRequest().authenticated()` pasa a `permitAll()`                                      | Deja pasar las peticiones sin sesión       |
| `autorizacion.patch`  | La regla de `/service/admin/**` pasa a `permitAll()` y se quitan los tres `@PreAuthorize` | Sin las dos capas, el usuario normal entra |
| `validacion.patch`    | Comenta `userValidator.validate(...)`                                                     | Permite registrar contraseñas distintas    |
| `errores.patch`       | Elimina el `if (user == null) return notFound()`                                          | El caso no encontrado termina en error 500 |

El flujo aplica cada parche, recompila, reinicia WebGoat, ejecuta la misma clase de
pruebas y revierte el parche. La prueba que corresponde al control eliminado falla; las
otras tres siguen pasando. Eso es lo que demuestra que cada prueba realmente cubre su
control y no otra cosa.
