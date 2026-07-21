'use strict';

function validateRequirementPayload(payload = {}) {
  const errors = [];

  if (!String(payload.area_destino || '').trim()) {
    errors.push('area_destino es requerido');
  }
  if (!String(payload.fecha_requerida || '').trim()) {
    errors.push('fecha_requerida es requerida');
  }
  if (!String(payload.creado_por || '').trim()) {
    errors.push('creado_por es requerido');
  }

  if (payload.items !== undefined && !Array.isArray(payload.items)) {
    errors.push('items debe ser un arreglo');
  }

  if (Array.isArray(payload.items)) {
    errors.push(...validateRequirementItems(payload.items));
  }

  return errors;
}

function validateRequirementItems(items = []) {
  const errors = [];

  items.forEach((item, index) => {
    if (!String(item?.numero_parte || '').trim()) {
      errors.push(`items[${index}].numero_parte es requerido`);
    }

    const normalized = normalizeRequirementItemQuantity(item);
    const hasStandardQuantity =
      item?.cantidad_estandarizada !== undefined &&
      item?.cantidad_estandarizada !== null &&
      String(item.cantidad_estandarizada).trim() !== '';
    const hasUnits =
      item?.cantidad_unidades !== undefined &&
      item?.cantidad_unidades !== null &&
      String(item.cantidad_unidades).trim() !== '';

    if (hasStandardQuantity !== hasUnits) {
      errors.push(
        `items[${index}] requiere cantidad_estandarizada y cantidad_unidades`,
      );
    } else if (
      hasStandardQuantity &&
      (normalized.cantidadEstandarizada === null ||
        normalized.cantidadUnidades === null)
    ) {
      errors.push(
        `items[${index}] requiere empaque y unidades enteras mayores que cero`,
      );
    }

    const quantity = normalized.cantidadRequerida;
    if (!Number.isInteger(quantity) || quantity <= 0) {
      errors.push(`items[${index}].cantidad_requerida debe ser un entero mayor que cero`);
    }
  });

  return errors;
}

function parseNullablePositiveInteger(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return null;
  }
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function normalizeRequirementItemQuantity(item = {}) {
  const cantidadEstandarizada = parseNullablePositiveInteger(
    item.cantidad_estandarizada,
  );
  const cantidadUnidades = parseNullablePositiveInteger(
    item.cantidad_unidades,
  );
  const directQuantity = Number(item.cantidad_requerida);

  return {
    cantidadRequerida:
      cantidadEstandarizada !== null && cantidadUnidades !== null
        ? cantidadEstandarizada * cantidadUnidades
        : directQuantity,
    cantidadEstandarizada,
    cantidadUnidades,
    unidadEmpaque: String(item.unidad_empaque || '').trim() || null,
    ubicacionDestino: String(item.ubicacion_destino || '').trim() || null,
  };
}

function canAppendRequirementItems(status) {
  return String(status || '').trim() === 'Pendiente';
}

function canCancelRequirement(status) {
  const normalized = String(status || '').trim();
  return normalized !== 'Cancelado' && normalized !== 'Entregado';
}

module.exports = {
  validateRequirementPayload,
  validateRequirementItems,
  normalizeRequirementItemQuantity,
  canAppendRequirementItems,
  canCancelRequirement,
};
