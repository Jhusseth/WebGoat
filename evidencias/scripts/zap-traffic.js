/*
 * Genera tráfico real sobre WebGoat haciendo que Chromium navegue a través del proxy de ZAP.
 * Así el escáner pasivo analiza exactamente el mismo tráfico que vería una persona usando
 * el navegador configurado con el proxy en el puerto 8090.
 */
const { chromium } = require('playwright');

const WEBGOAT_URL = process.env.WEBGOAT_URL || 'http://runner:8080/WebGoat';
const ZAP_PROXY = process.env.ZAP_PROXY || 'http://zap:8090';

async function visitar(page, ruta, descripcion) {
  try {
    const respuesta = await page.goto(`${WEBGOAT_URL}${ruta}`, {
      waitUntil: 'domcontentloaded',
      timeout: 20000,
    });
    console.log(`[ok] ${descripcion} -> ${respuesta ? respuesta.status() : 'sin respuesta'}`);
  } catch (error) {
    console.log(`[aviso] ${descripcion} -> ${error.message}`);
  }
}

(async () => {
  console.log(`Navegando ${WEBGOAT_URL} a través del proxy ${ZAP_PROXY}`);
  const browser = await chromium.launch({
    proxy: { server: ZAP_PROXY },
    args: ['--proxy-bypass-list=<-loopback>', '--no-sandbox'],
  });
  const context = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await context.newPage();

  await visitar(page, '/login', 'página de login');

  try {
    await page.fill('input[name="username"]', 'webgoat-user');
    await page.fill('input[name="password"]', 'webgoat');
    await page.click('button[type="submit"]');
    await page.waitForLoadState('domcontentloaded');
    console.log('[ok] inicio de sesión con webgoat-user');
  } catch (error) {
    console.log(`[aviso] inicio de sesión -> ${error.message}`);
  }

  await visitar(page, '/welcome.mvc', 'página de bienvenida');
  await visitar(page, '/start.mvc', 'listado de lecciones');
  await visitar(page, '/service/reportcard.mvc', 'report card');
  await visitar(page, '/service/lessonoverview.mvc', 'resumen de lecciones');
  await visitar(page, '/mail', 'buzón de correo');
  await visitar(page, '/registration', 'formulario de registro');
  await visitar(page, '/service/admin/users', 'endpoint de administración (esperado 403)');
  await visitar(page, '/HttpBasics.lesson.lesson', 'lección HttpBasics');
  await visitar(page, '/SqlInjection.lesson.lesson', 'lección SQL Injection');

  // Envío inválido en el formulario de registro: genera tráfico POST con errores de validación.
  await visitar(page, '/registration', 'formulario de registro (segunda visita)');
  try {
    await page.fill('input[name="username"]', 'usuario-invalido-!');
    await page.fill('input[name="password"]', '123');
    await page.fill('input[name="matchingPassword"]', '456');
    const agree = await page.$('input[name="agree"]');
    if (agree) {
      await agree.check();
    }
    await page.click('button[type="submit"]');
    await page.waitForLoadState('domcontentloaded');
    console.log('[ok] envío de registro con datos inválidos');
  } catch (error) {
    console.log(`[aviso] envío de registro inválido -> ${error.message}`);
  }

  await browser.close();
  console.log('Navegación finalizada.');
})().catch((error) => {
  console.error('Error en la navegación:', error);
  process.exit(1);
});
