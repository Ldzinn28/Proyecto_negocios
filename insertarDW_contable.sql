USE DW_contable;

-- 1. LIMPIEZA INICIAL CON CONTROL DE INTEGRIDAD
SET FOREIGN_KEY_CHECKS = 0;

DELETE FROM fact_compras;
DELETE FROM fact_bancarizacion;
DELETE FROM fact_control_fiscal_ventas;

DELETE FROM d_tiempo;
DELETE FROM d_empresa;
DELETE FROM d_proveedor;
DELETE FROM d_cuenta_contable;
DELETE FROM d_entidad_financiera;
DELETE FROM d_personal;

SET FOREIGN_KEY_CHECKS = 1;

-- ==============================================================================
-- 2. CARGA DE TABLAS DE DIMENSIÓN
-- ==============================================================================

-- A. Dimensión Tiempo (Unifica TODAS las fuentes de fechas del sistema)
INSERT IGNORE INTO d_tiempo (id_fecha, fecha, anio, mes, nombre_mes, trimestre, semana_anio)
SELECT DISTINCT
    (YEAR(fecha_unica) * 10000 + MONTH(fecha_unica) * 100 + DAY(fecha_unica)) AS id_fecha,
    DATE(fecha_unica) AS fecha,
    YEAR(fecha_unica) AS anio,
    MONTH(fecha_unica) AS mes,
    MONTHNAME(fecha_unica) AS nombre_mes,
    QUARTER(fecha_unica) AS trimestre,
    WEEKOFYEAR(fecha_unica) AS semana_anio
FROM (
    SELECT fechaProv AS fecha_unica FROM dyjdb.compra WHERE fechaProv IS NOT NULL
    UNION 
    SELECT DATE(fecha) AS fecha_unica FROM dyjdb.bancarizacion_detalle WHERE fecha IS NOT NULL
    UNION 
    SELECT fechaCliente AS fecha_unica FROM dyjdb.ventaestandar WHERE fechaCliente IS NOT NULL
    UNION 
    SELECT created_at AS fecha_unica FROM dyjdb.control_registros WHERE created_at IS NOT NULL
    UNION
    SELECT STR_TO_DATE(CONCAT(s.ano, '-', 
        CASE s.mes 
            WHEN 'Enero' THEN 1 WHEN 'Febrero' THEN 2 WHEN 'Marzo' THEN 3 WHEN 'Abril' THEN 4 
            WHEN 'Mayo' THEN 5 WHEN 'Junio' THEN 6 WHEN 'Julio' THEN 7 WHEN 'Agosto' THEN 8 
            WHEN 'Septiembre' THEN 9 WHEN 'Octubre' THEN 10 WHEN 'Noviembre' THEN 11 WHEN 'Diciembre' THEN 12
            ELSE 1
        END, '-01'), '%Y-%c-%d') AS fecha_unica 
    FROM dyjdb.seguimiento s WHERE s.ano IS NOT NULL AND s.mes IS NOT NULL
) AS FechasUnificadas
WHERE fecha_unica IS NOT NULL
ORDER BY id_fecha;

-- B. Dimensión Empresa
INSERT INTO d_empresa (id_empresa, razon_social, nit, direccion_fiscal, actividad_economica, mes_cierre)
SELECT 
    e.idempresa,
    e.razonSocial,
    e.nit,
    e.direccionFiscal,
    IFNULL(act.nombre, IFNULL(e.actividad, 'Sin Actividad Registrada')),
    e.mesCierre
FROM dyjdb.empresa e
LEFT JOIN dyjdb.empresaactividad ea ON e.idempresa = ea.idempresa
LEFT JOIN dyjdb.actividad act ON ea.idactividad = act.idActividad
GROUP BY e.idempresa;

-- C. Dimensión Proveedor
INSERT INTO d_proveedor (nit_proveedor, razon_social)
SELECT 
    nitProv, 
    razonSocialProv
FROM (
    SELECT nitProv, razonSocialProv FROM dyjdb.compra
    UNION
    SELECT nitProv, razonSocialProv FROM dyjdb.compraestandar
) AS ProvUnicos
WHERE nitProv IS NOT NULL AND razonSocialProv IS NOT NULL
GROUP BY nitProv, razonSocialProv;

-- D. Dimensión Cuenta Contable
INSERT INTO d_cuenta_contable (id_cuenta, codigo_cuenta, descripcion, vida_util, porcentaje_depreciacion)
SELECT 
    c.idcuenta,
    c.cod,
    c.nombre,
    IFNULL(af.vidautil, 0),
    IFNULL(af.pdep, 0)
FROM dyjdb.cuenta c
LEFT JOIN dyjdb.af_cuentas af ON c.cod = af.codigo;

-- E. Dimensión Entidad Financiera
INSERT INTO d_entidad_financiera (id_entidad, nombre, sigla, nit)
SELECT 
    identidad, 
    nombre, 
    sigla, 
    nit 
FROM dyjdb.bancarizacion_entidades_financieras;

-- F. Dimensión Personal (Con registro comodín seguro)
INSERT INTO d_personal (id_personal, nombre_completo, ci, cargo, AREA, relacion_laboral, nacionalidad)
SELECT 
    p.idpersona,
    IFNULL(p.fullname, CONCAT(p.paterno, ' ', IFNULL(p.materno,''), ' ', p.nombre)),
    p.ci,
    IFNULL(c.descripcion, 'Sin Cargo'),
    IFNULL(ar.descripcion, 'Sin Área'),
    IFNULL(l.laboral, 'Indefinido'),
    IFNULL(nac.pais, 'Boliviano(a)')
FROM dyjdb.persona p
LEFT JOIN dyjdb.af_personal ap ON p.idpersona = ap.idpersonal
LEFT JOIN dyjdb.af_cargo c ON ap.cargo = c.idcargo
LEFT JOIN dyjdb.af_area ar ON ap.area = ar.idarea
LEFT JOIN dyjdb.af_laboral l ON ap.relacionlab = l.idlaboral
LEFT JOIN dyjdb.af_nacionalidades nac ON ap.nacionalidad = nac.idnac

UNION ALL

SELECT 1, 'Sin Responsable Asignado', '0', 'Sin Cargo', 'Sin Área', 'Indefinido', 'Boliviano(a)'
WHERE NOT EXISTS (SELECT 1 FROM d_personal WHERE id_personal = 1);

-- ==============================================================================
-- 3. CARGA DE TABLAS DE HECHOS (FACTS)
-- ==============================================================================

-- Fact 1: Compras y Crédito Fiscal (R1)
INSERT INTO fact_compras (
    id_compra_oltp, id_fecha, id_empresa, id_proveedor, id_cuenta,
    total_factura, total_ice, importe_exento, importe_neto, credito_fiscal, descuentos
)
SELECT 
    c.idcompra,
    (YEAR(c.fechaProv) * 10000 + MONTH(c.fechaProv) * 100 + DAY(c.fechaProv)) AS id_fecha,
    pv.idEmpresa,
    p.id_proveedor,
    c.idcuenta,
    c.totalFact,
    c.totalIce,
    c.importexecto,
    c.importeNeto,
    c.creditoFiscal,
    c.descuentos
FROM dyjdb.compra c
JOIN dyjdb.puntoventa pv ON c.idPuntoVenta = pv.idPuntoVenta
JOIN d_proveedor p ON c.nitProv = p.nit_proveedor AND c.razonSocialProv = p.razon_social;

-- Fact 2: Transacciones de Bancarización (R2)
INSERT INTO fact_bancarizacion (
    id_detalle_oltp, id_fecha, id_empresa, id_entidad,
    monto_percibido, tipo_transaccion, forma_pago, es_excluido
)
SELECT 
    bd.iddetalle,
    (YEAR(bd.fecha) * 10000 + MONTH(bd.fecha) * 100 + DAY(bd.fecha)) AS id_fecha,
    bd.idempresa,
    ef.id_entidad,
    IFNULL(bd.monto_percibido, 0.00),
    bd.tipo_transaccion,
    bd.forma_pago,
    bd.excluido
FROM dyjdb.bancarizacion_detalle bd
LEFT JOIN d_entidad_financiera ef ON bd.nit_entidad_financiera = ef.nit;

-- Fact 3: Control Fiscal, Ventas y Saldos Mensuales (R3 y R4)
INSERT INTO fact_control_fiscal_ventas (
    id_registro_oltp, 
    id_fecha, 
    id_empresa, 
    id_personal,
    total_ventas, 
    total_compras, 
    monto_iva, 
    monto_it,
    saldo_iva, 
    saldo_iue, 
    monto_comision, 
    monto_total, 
    estado_registro
)
SELECT 
    s.idsgto AS id_registro_oltp,
    dt.id_fecha,
    IFNULL(s.idempresa, 1) AS id_empresa,
    IFNULL(dp.id_personal, 1) AS id_personal,
    IFNULL(s.ventas, 0.00),
    IFNULL(s.compras, 0.00),
    IFNULL(s.iva, 0.00),
    IFNULL(s.it, 0.00),
    IFNULL(s.saldoiva, 0.00),
    IFNULL(s.saldoiue, 0.00),
    IFNULL(s.comision, 0.00),
    IFNULL(s.total, 0.00),
    CASE 
        WHEN s.cancelado = 1 THEN 'aprobado'
        WHEN s.pago > 0 THEN 'enviado'
        ELSE 'borrador'
    END AS estado_registro
FROM dyjdb.seguimiento s
JOIN d_tiempo dt ON dt.id_fecha = (s.ano * 10000 + 
     CASE 
        WHEN CAST(s.mes AS CHAR) = 'Enero' THEN 1 
        WHEN CAST(s.mes AS CHAR) = 'Febrero' THEN 2 
        WHEN CAST(s.mes AS CHAR) = 'Marzo' THEN 3 
        WHEN CAST(s.mes AS CHAR) = 'Abril' THEN 4 
        WHEN CAST(s.mes AS CHAR) = 'Mayo' THEN 5 
        WHEN CAST(s.mes AS CHAR) = 'Junio' THEN 6 
        WHEN CAST(s.mes AS CHAR) = 'Julio' THEN 7 
        WHEN CAST(s.mes AS CHAR) = 'Agosto' THEN 8 
        WHEN CAST(s.mes AS CHAR) = 'Septiembre' THEN 9 
        WHEN CAST(s.mes AS CHAR) = 'Octubre' THEN 10 
        WHEN CAST(s.mes AS CHAR) = 'Noviembre' THEN 11 
        WHEN CAST(s.mes AS CHAR) = 'Diciembre' THEN 12
        -- Si en la tabla el mes a veces ya viene registrado como número ('1', '2', etc.)
        WHEN CAST(s.mes AS CHAR) REGEXP '^[0-9]+$' THEN CAST(s.mes AS UNSIGNED)
        ELSE 1
     END * 100 + 1)
LEFT JOIN d_personal dp ON s.idresponsable = dp.id_personal

UNION ALL

SELECT 
    MAX(ve.idventa) AS id_registro_oltp,
    (YEAR(ve.fechaCliente) * 10000 + MONTH(ve.fechaCliente) * 100 + DAY(ve.fechaCliente)) AS id_fecha,
    IFNULL(pv.idEmpresa, 1) AS id_empresa,
    IFNULL(dp.id_personal, 1) AS id_personal,
    SUM(IFNULL(ve.importeTotal, 0.00)) AS total_ventas,
    0.00 AS total_compras,
    SUM(IFNULL(ve.debitofiscal, 0.00)) AS monto_iva,
    SUM(IFNULL(ve.importeTotal, 0.00) * 0.03) AS monto_it,
    0.00 AS saldo_iva,
    0.00 AS saldo_iue,
    0.00 AS monto_comision,
    SUM(IFNULL(ve.importeTotal, 0.00)) AS monto_total,
    'aprobado' AS estado_registro
FROM dyjdb.ventaestandar ve
JOIN d_tiempo dt ON dt.id_fecha = (YEAR(ve.fechaCliente) * 10000 + MONTH(ve.fechaCliente) * 100 + DAY(ve.fechaCliente))
LEFT JOIN dyjdb.puntoventa pv ON ve.idPuntoVenta = pv.idPuntoVenta
LEFT JOIN d_personal dp ON ve.idresponsable = dp.id_personal
WHERE ve.fechaCliente IS NOT NULL
GROUP BY YEAR(ve.fechaCliente), MONTH(ve.fechaCliente), DAY(ve.fechaCliente), pv.idEmpresa, IFNULL(dp.id_personal, 1);