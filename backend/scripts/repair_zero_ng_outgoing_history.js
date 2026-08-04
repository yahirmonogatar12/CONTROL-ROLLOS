const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const { pool } = require('../config/database');
const {
  repairZeroNgOutgoingHistory
} = require('../services/outgoingHistoryRepairService');

function readNumericArgument(name) {
  const prefix = `--${name}=`;
  const raw = process.argv.find((argument) => argument.startsWith(prefix));
  if (!raw) return undefined;

  const value = Number(raw.slice(prefix.length));
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`El argumento --${name} debe ser un número mayor o igual a cero`);
  }
  return value;
}

async function main() {
  const apply = process.argv.includes('--apply');
  const expectedCount = readNumericArgument('expected-count');
  const expectedTotal = readNumericArgument('expected-total');

  const result = await repairZeroNgOutgoingHistory(pool, {
    apply,
    expectedCount,
    expectedTotal
  });

  console.log(JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    candidates: result.before.count,
    candidate_quantity: result.before.totalQuantity,
    repaired: result.repaired.count,
    repaired_quantity: result.repaired.totalQuantity
  }));
}

if (require.main === module) {
  main()
    .catch((error) => {
      console.error(`ERROR: ${error.message}`);
      process.exitCode = 1;
    })
    .finally(async () => {
      await pool.end();
    });
}

module.exports = { main, readNumericArgument };
