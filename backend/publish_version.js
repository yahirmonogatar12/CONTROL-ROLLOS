/**
 * Script para publicar nueva versión de la aplicación
 * 
 * USO:
 *   node publish_version.js
 * 
 * También puedes pasar parámetros:
 *   node publish_version.js --version 1.0.9 --url "https://..." --notes "Cambios..." --mandatory
 */

require('dotenv').config();
const pool = require('./config/database');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

const question = (prompt) => new Promise(resolve => rl.question(prompt, resolve));

async function main() {
  console.log('\n============================================');
  console.log('   PUBLICAR NUEVA VERSIÓN');
  console.log('============================================\n');
  
  // Parsear argumentos de línea de comandos
  const args = process.argv.slice(2);
  let version = null;
  let downloadUrl = null;
  let releaseNotes = null;
  let isMandatory = false;
  
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--version' && args[i+1]) version = args[++i];
    if (args[i] === '--url' && args[i+1]) downloadUrl = args[++i];
    if (args[i] === '--notes' && args[i+1]) releaseNotes = args[++i];
    if (args[i] === '--mandatory') isMandatory = true;
  }
  
  try {
    // Obtener versión actual
    const versionFile = path.join(__dirname, '..', 'VERSION.txt');
    let currentVersion = '1.0.0';
    if (fs.existsSync(versionFile)) {
      currentVersion = fs.readFileSync(versionFile, 'utf8').trim();
    }
    
    // Obtener última versión publicada
    const [lastVersion] = await pool.query(
      'SELECT version, release_date FROM app_versions ORDER BY release_date DESC LIMIT 1'
    );
    
    if (lastVersion.length > 0) {
      console.log(`📌 Última versión publicada: ${lastVersion[0].version} (${lastVersion[0].release_date})`);
    }
    console.log(`📁 Versión en VERSION.txt: ${currentVersion}\n`);
    
    // Solicitar datos interactivamente si no se proporcionaron
    if (!version) {
      version = await question(`Nueva versión [${currentVersion}]: `);
      if (!version) version = currentVersion;
    }
    
    // Verificar si ya existe
    const [existing] = await pool.query(
      'SELECT id FROM app_versions WHERE version = ?',
      [version]
    );
    
    if (existing.length > 0) {
      console.log(`\n⚠️  La versión ${version} ya existe.`);
      const update = await question('¿Desea actualizarla? (s/n): ');
      if (update.toLowerCase() !== 's') {
        console.log('Operación cancelada.');
        process.exit(0);
      }
    }
    
    if (!downloadUrl) {
      downloadUrl = await question('URL de descarga (o Enter para omitir): ');
    }
    
    if (!releaseNotes) {
      console.log('\nNotas de la versión (termina con línea vacía):');
      const lines = [];
      let line;
      while ((line = await question('')) !== '') {
        lines.push(line);
      }
      releaseNotes = lines.join('\n');
    }
    
    if (!args.includes('--mandatory')) {
      const mandatory = await question('¿Es obligatoria? (s/N): ');
      isMandatory = mandatory.toLowerCase() === 's';
    }
    
    // Confirmar
    console.log('\n============================================');
    console.log('RESUMEN DE LA PUBLICACIÓN:');
    console.log('============================================');
    console.log(`Versión: ${version}`);
    console.log(`URL: ${downloadUrl || '(sin URL)'}`);
    console.log(`Obligatoria: ${isMandatory ? 'SÍ' : 'NO'}`);
    console.log(`Notas:\n${releaseNotes || '(sin notas)'}`);
    console.log('============================================\n');
    
    const confirm = await question('¿Publicar esta versión? (s/N): ');
    if (confirm.toLowerCase() !== 's') {
      console.log('Operación cancelada.');
      process.exit(0);
    }
    
    // Insertar o actualizar
    if (existing.length > 0) {
      await pool.query(`
        UPDATE app_versions SET
          download_url = ?,
          release_notes = ?,
          is_mandatory = ?,
          release_date = NOW()
        WHERE version = ?
      `, [downloadUrl || null, releaseNotes || null, isMandatory ? 1 : 0, version]);
      console.log(`\n✅ Versión ${version} ACTUALIZADA correctamente.`);
    } else {
      await pool.query(`
        INSERT INTO app_versions (version, download_url, release_notes, is_mandatory, created_by)
        VALUES (?, ?, ?, ?, ?)
      `, [version, downloadUrl || null, releaseNotes || null, isMandatory ? 1 : 0, 'publish_script']);
      console.log(`\n✅ Versión ${version} PUBLICADA correctamente.`);
    }
    
    // Actualizar VERSION.txt
    const updateVersionFile = await question(`\n¿Actualizar VERSION.txt a ${version}? (s/N): `);
    if (updateVersionFile.toLowerCase() === 's') {
      fs.writeFileSync(versionFile, version);
      console.log('✅ VERSION.txt actualizado.');
    }
    
    console.log('\n🎉 ¡Listo! Los usuarios verán la actualización la próxima vez que inicien sesión.\n');
    
  } catch (err) {
    console.error('❌ Error:', err.message);
  } finally {
    rl.close();
    process.exit(0);
  }
}

main();
