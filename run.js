// Lanzador no interactivo para nightscout-to-libreview.
//
// El index.js original pide los datos por consola y sólo acepta meses
// naturales. Este arranque reutiliza sus funciones tal cual (src/functions/*
// no se toca) pero coge la configuración de variables de entorno y admite un
// rango de fechas cualquiera, para poder lanzarlo desde cron o a mano.
//
// El DeviceId debe ser ESTABLE entre ejecuciones: LibreView lo trata como un
// teléfono dado de alta, y uno nuevo cada vez ensucia la cuenta con
// dispositivos duplicados. Se persiste en device.json.
const fs = require('fs');
const uuid = require('uuid');
const libre = require('./src/functions/libre');
const nightscout = require('./src/functions/nightscout');

const {
  NS_URL, NS_TOKEN, LV_USER, LV_PASS,
  FROM_DATE, TO_DATE, DRY_RUN,
} = process.env;

const requeridas = DRY_RUN === 'true'
  ? { NS_URL, FROM_DATE, TO_DATE }              // en seco no hace falta LibreView
  : { NS_URL, LV_USER, LV_PASS, FROM_DATE, TO_DATE };
for (const [k, v] of Object.entries(requeridas)) {
  if (!v) { console.error(`falta la variable ${k}`); process.exit(1); }
}

const DEVICE_FILE = '/state/device.json';
let device;
if (fs.existsSync(DEVICE_FILE)) {
  device = JSON.parse(fs.readFileSync(DEVICE_FILE)).device;
  console.log('device reutilizado', device);
} else {
  device = uuid.v4().toUpperCase();
  fs.writeFileSync(DEVICE_FILE, JSON.stringify({ device, creado: new Date().toISOString() }));
  console.log('device NUEVO', device);
}

(async () => {
  console.log(`rango ${FROM_DATE} .. ${TO_DATE}`);
  const glucose = await nightscout.getNightscoutGlucoseEntries(NS_URL, NS_TOKEN || '', FROM_DATE, TO_DATE);
  const food = await nightscout.getNightscoutFoodEntries(NS_URL, NS_TOKEN || '', FROM_DATE, TO_DATE);
  const insulin = await nightscout.getNightscoutInsulinEntries(NS_URL, NS_TOKEN || '', FROM_DATE, TO_DATE);

  console.log(`leído de nightscout -> glucosa ${glucose.length}, comida ${food.length}, insulina ${insulin.length}`);
  if (!glucose.length && !food.length && !insulin.length) {
    console.log('nada que subir'); return;
  }
  if (DRY_RUN === 'true') {
    console.log('DRY_RUN: no se sube nada a LibreView.');
    console.log('primera lectura:', JSON.stringify(glucose[0]));
    console.log('última  lectura:', JSON.stringify(glucose[glucose.length - 1]));
    return;
  }

  const token = await libre.authLibreView(LV_USER, LV_PASS, device, true);
  if (!token) { console.error('login de LibreView fallido'); process.exit(2); }

  await libre.transferLibreView(device, token, glucose, food, insulin);
  const ultimo = glucose.map(g => g.timestamp).sort().pop();
  console.log('subida terminada; ultimo=' + ultimo);
})().catch(e => {
  console.error('ERROR:', e.response ? JSON.stringify(e.response.data) : e.message);
  process.exit(3);
});
