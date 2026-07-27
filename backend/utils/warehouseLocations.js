'use strict';

function normalizeWarehouseLocation(value) {
  return String(value || '').trim().toUpperCase();
}

function warehouseLocationKey(value) {
  return normalizeWarehouseLocation(value).replace(/\s+/g, '');
}

function splitConfiguredWarehouseLocations(value) {
  return String(value || '')
    .split(',')
    .map(warehouseLocationKey)
    .filter(Boolean);
}

function configuredWarehouseLocationsInclude(configuredLocations, location) {
  const locationKey = warehouseLocationKey(location);
  return locationKey !== '' &&
    splitConfiguredWarehouseLocations(configuredLocations).includes(locationKey);
}

module.exports = {
  normalizeWarehouseLocation,
  warehouseLocationKey,
  splitConfiguredWarehouseLocations,
  configuredWarehouseLocationsInclude,
};
