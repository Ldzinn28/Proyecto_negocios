USE DW_contable;

-- Vista 1: R1. Resumen de Compras y Crédito Fiscal (Alimenta Chart 1)
CREATE OR REPLACE VIEW v_superset_compras_fiscal AS
SELECT 
    fc.id_fact_compra,
    t.fecha,
    t.anio,
    t.nombre_mes,
    e.razon_social AS empresa_cliente,
    p.nit_proveedor,
    p.razon_social AS proveedor,
    c.codigo_cuenta,
    c.descripcion AS cuenta_contable,
    fc.total_factura,
    fc.importe_neto,
    fc.credito_fiscal,
    fc.descuentos
FROM fact_compras fc
JOIN d_tiempo t ON fc.id_fecha = t.id_fecha
JOIN d_empresa e ON fc.id_empresa = e.id_empresa
JOIN d_proveedor p ON fc.id_proveedor = p.id_proveedor
LEFT JOIN d_cuenta_contable c ON fc.id_cuenta = c.id_cuenta;

-- Vista 2: R2. Trazabilidad de Bancarización (Alimenta Chart 2)
CREATE OR REPLACE VIEW v_superset_bancarizacion AS
SELECT 
    fb.id_fact_bancarizacion, 
    t.fecha, 
    t.anio, 
    t.nombre_mes,
    e.razon_social AS empresa, 
    -- REEMPLAZO DE NULLS AQUÍ:
    COALESCE(ef.nombre, 'Sin Banco Registrado') AS banco_entidad, 
    COALESCE(ef.sigla, 'S/B') AS sigla_banco,
    fb.monto_percibido, 
    fb.tipo_transaccion, 
    fb.forma_pago, 
    fb.es_excluido
FROM fact_bancarizacion fb
JOIN d_tiempo t ON fb.id_fecha = t.id_fecha
JOIN d_empresa e ON fb.id_empresa = e.id_empresa
LEFT JOIN d_entidad_financiera ef ON fb.id_entidad = ef.id_entidad;

-- Vista 3: R3 y R4. Control Fiscal, Ventas e Impuestos (Alimenta Charts 3 y 4)
CREATE OR REPLACE VIEW v_superset_control_fiscal AS

SELECT 
    fcf.id_fact_control AS id_transaccion,
    t.fecha,
    t.anio,
    t.nombre_mes,
    e.razon_social AS empresa,
    IFNULL(e.actividad_economica, 'General') AS actividad_economica,
    IFNULL(per.nombre_completo, 'Sin Asignar') AS responsable,
    fcf.total_ventas AS total_ventas,
    0.00000 AS total_compras,
    fcf.monto_iva,
    fcf.monto_it,
    fcf.saldo_iva,
    fcf.saldo_iue,
    fcf.monto_comision,
    fcf.monto_total AS total_impuestos_apagar,
    fcf.estado_registro
FROM fact_control_fiscal_ventas fcf
LEFT JOIN d_tiempo t ON fcf.id_fecha = t.id_fecha
LEFT JOIN d_empresa e ON fcf.id_empresa = e.id_empresa
LEFT JOIN d_personal per ON fcf.id_personal = per.id_personal

UNION ALL

-- 2. REGISTROS DE COMPRAS REALES (desde fact_compras)
SELECT 
    fc.id_fact_compra AS id_transaccion,
    t.fecha,
    t.anio,
    t.nombre_mes,
    e.razon_social AS empresa,
    IFNULL(e.actividad_economica, 'General') AS actividad_economica,
    'Sin Asignar' AS responsable,
    0.00000 AS total_ventas,
    fc.total_factura AS total_compras,
    fc.credito_fiscal AS monto_iva,
    0.00000 AS monto_it,
    0.00000 AS saldo_iva,
    0.00000 AS saldo_iue,
    0.00000 AS monto_comision,
    fc.total_factura AS total_impuestos_apagar,
    'VALIDO' AS estado_registro
FROM fact_compras fc
LEFT JOIN d_tiempo t ON fc.id_fecha = t.id_fecha
LEFT JOIN d_empresa e ON fc.id_empresa = e.id_empresa;
