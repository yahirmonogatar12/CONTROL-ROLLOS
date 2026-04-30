/**
 * Permissions Configuration
 * Constantes de permisos por departamento
 */

// Departamentos con acceso completo al sistema
const FULL_ACCESS_DEPARTMENTS = ['Sistemas', 'Gerencia', 'Administración'];

// Departamentos con permiso de escritura en Warehousing (entrada de material)
const WAREHOUSING_WRITE_DEPARTMENTS = [...FULL_ACCESS_DEPARTMENTS, 'Almacén', 'Almacén Supervisor'];

// Departamentos con permiso de escritura en Outgoing (salida de material)
const OUTGOING_WRITE_DEPARTMENTS = [...FULL_ACCESS_DEPARTMENTS, 'Almacén', 'Almacén Supervisor'];

// Departamentos con permiso de escritura en IQC (inspección de calidad)
const IQC_WRITE_DEPARTMENTS = [...FULL_ACCESS_DEPARTMENTS, 'Calidad', 'Calidad Supervisor'];

// Departamentos con permiso para INICIAR/TERMINAR auditorías (supervisores en PC)
const AUDIT_MANAGE_DEPARTMENTS = [...FULL_ACCESS_DEPARTMENTS, 'Almacén Supervisor'];

// Departamentos con permiso para ESCANEAR durante auditorías (operadores en móvil)
const AUDIT_SCAN_DEPARTMENTS = [...FULL_ACCESS_DEPARTMENTS, 'Almacén', 'Almacén Supervisor'];

// Departamentos con permiso para APROBAR discrepancias de auditoría y generar salidas
const AUDIT_APPROVE_DISCREPANCY_DEPARTMENTS = [...FULL_ACCESS_DEPARTMENTS, 'Almacén Supervisor'];

module.exports = {
  FULL_ACCESS_DEPARTMENTS,
  WAREHOUSING_WRITE_DEPARTMENTS,
  OUTGOING_WRITE_DEPARTMENTS,
  IQC_WRITE_DEPARTMENTS,
  AUDIT_MANAGE_DEPARTMENTS,
  AUDIT_SCAN_DEPARTMENTS,
  AUDIT_APPROVE_DISCREPANCY_DEPARTMENTS
};
