const mysql = require('mysql2/promise');

(async () => {
  const pool = await mysql.createPool({
    host: 'up-de-fra1-mysql-1.db.run-on-seenode.com',
    port: 11550,
    user: 'db_rrpq0erbdujn',
    password: '5fUNbSRcPP3LN9K2I33Pr0ge',
    database: 'db_rrpq0erbdujn'
  });
  
  console.log('=== Entradas de 0CE476VF6DC (las que mostraban "18") ===');
  const [rows] = await pool.query(`
    SELECT codigo_material_recibido, ubicacion_salida, ubicacion_destino, 
           COALESCE(ubicacion_destino, ubicacion_salida) as location
    FROM control_material_almacen_smd
    WHERE numero_parte = '0CE476VF6DC'
    LIMIT 10
  `);
  console.log(rows);
  
  process.exit(0);
})();
