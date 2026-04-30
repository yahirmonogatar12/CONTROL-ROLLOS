-- Script de pruebas para triggers `_smd` (ejecutar en STAGING)
-- NOTA: los INSERT de prueba están comentados — descomentar con cuidado.

-- 1) Ver triggers instalados
SELECT TRIGGER_NAME, EVENT_OBJECT_TABLE, ACTION_TIMING, EVENT_MANIPULATION
 FROM INFORMATION_SCHEMA.TRIGGERS
 WHERE TRIGGER_SCHEMA = DATABASE() AND TRIGGER_NAME LIKE 'trg\_%\_smd';

-- 2) Ver índices únicos en inventario_lotes_smd
SHOW INDEX FROM inventario_lotes_smd;

-- 3) Pruebas manuales (ejecutar una por una)
-- a) Insertar entrada en control_material_almacen_smd (debe sumar en inventario_lotes_smd)
-- INSERT INTO control_material_almacen_smd (codigo_material_recibido, numero_parte, numero_lote_material, cantidad_actual, iqc_status, fecha_recibo)
-- VALUES ('TEST-ETIQ-001','PN-001','L-001', 100, 'Released', NOW());

-- b) Insertar salida en control_material_salida_smd (debe sumar total_salida)
-- INSERT INTO control_material_salida_smd (codigo_material_recibido, numero_parte, numero_lote, cantidad_salida, fecha_salida)
-- VALUES ('TEST-ETIQ-001','PN-001','L-001', 10, NOW());

-- c) Insertar devolución en material_return_smd (debe restar total_salida)
-- INSERT INTO material_return_smd (material_warehousing_code, part_number, material_lot_no, return_qty)
-- VALUES ('TEST-ETIQ-001','PN-001','L-001', 5);

-- 4) Comprobaciones de resultado
-- SELECT * FROM inventario_lotes_smd WHERE codigo_material_recibido = 'TEST-ETIQ-001' AND numero_parte = 'PN-001' AND numero_lote = 'L-001';

-- 5) Limpieza de ejemplo (si se usaron datos de prueba)
-- DELETE FROM control_material_almacen_smd WHERE codigo_material_recibido = 'TEST-ETIQ-001';
-- DELETE FROM control_material_salida_smd WHERE codigo_material_recibido = 'TEST-ETIQ-001';
-- DELETE FROM material_return_smd WHERE material_warehousing_code = 'TEST-ETIQ-001';
-- DELETE FROM inventario_lotes_smd WHERE codigo_material_recibido = 'TEST-ETIQ-001';
