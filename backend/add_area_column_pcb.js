// Manual PCB schema migration helper.
// Uses the same .env resolution as server.js and applies only PCB inventory fixes.
const fs = require('fs');
const path = require('path');

function getEnvPath() {
  const exeDir = path.dirname(process.execPath);
  const exeEnvPath = path.join(exeDir, '.env');

  if (fs.existsSync(exeEnvPath)) {
    return exeEnvPath;
  }

  const devEnvPath = path.join(__dirname, '.env');
  if (fs.existsSync(devEnvPath)) {
    return devEnvPath;
  }

  return path.join(process.cwd(), '.env');
}

require('dotenv').config({ path: getEnvPath() });

const { pool } = require('./config/database');
const {
  migratePcbInventorySchema,
  addPcbInventoryTipoMovimiento,
} = require('./utils/dbMigrations');

async function main() {
  try {
    console.log('Migrando esquema PCB...');
    await migratePcbInventorySchema();
    await addPcbInventoryTipoMovimiento();
    console.log('Migracion PCB completa');
  } catch (error) {
    console.error('Error migrando esquema PCB:', error.message);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
}

main();
