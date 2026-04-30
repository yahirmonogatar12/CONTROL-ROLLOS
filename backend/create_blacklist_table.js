/**
 * Migration script to create blacklisted_lots table
 */
const db = require('./config/database');

async function createBlacklistTable() {
  const pool = await db.getPool();
  
  const sql = `
    CREATE TABLE IF NOT EXISTS blacklisted_lots (
      id INT AUTO_INCREMENT PRIMARY KEY,
      lot_number VARCHAR(100) NOT NULL UNIQUE,
      reason TEXT NULL,
      blocked_by VARCHAR(100) NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_blacklisted_lot (lot_number)
    )
  `;
  
  try {
    await pool.query(sql);
    console.log('✅ Table blacklisted_lots created successfully');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error creating table:', error.message);
    process.exit(1);
  }
}

createBlacklistTable();
