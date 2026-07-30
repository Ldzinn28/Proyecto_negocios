DROP DATABASE IF EXISTS DW_contable;
CREATE DATABASE DW_contable;
USE DW_contable;

-- 1. TABLAS DE DIMENSIÓN 

-- Dimensión Tiempo
CREATE TABLE d_tiempo (
    id_fecha INT PRIMARY KEY,
    fecha DATE NOT NULL,
    anio INT NOT NULL,
    mes INT NOT NULL,
    nombre_mes VARCHAR(20) NOT NULL,
    trimestre INT NOT NULL,
    semana_anio INT NOT NULL
);

-- Dimensión Empresa (Consolida empresa, punto de venta y actividad)
CREATE TABLE d_empresa (
    id_empresa INT PRIMARY KEY, 
    razon_social VARCHAR(200) NOT NULL,
    nit BIGINT NOT NULL,
    direccion_fiscal VARCHAR(150),
    actividad_economica VARCHAR(255),
    mes_cierre VARCHAR(45)
);

-- Dimensión Proveedor
CREATE TABLE d_proveedor (
    id_proveedor INT AUTO_INCREMENT PRIMARY KEY,
    nit_proveedor BIGINT NOT NULL,
    razon_social VARCHAR(200) NOT NULL
);

-- Dimensión Cuenta Contable
CREATE TABLE d_cuenta_contable (
    id_cuenta INT PRIMARY KEY,
    codigo_cuenta VARCHAR(30),
    descripcion VARCHAR(250),
    vida_util FLOAT DEFAULT 0,
    porcentaje_depreciacion FLOAT DEFAULT 0
);

-- Dimensión Entidad Financiera (Bancos)
CREATE TABLE d_entidad_financiera (
    id_entidad INT PRIMARY KEY,
    nombre VARCHAR(200) NOT NULL,
    sigla VARCHAR(20),
    nit VARCHAR(20)
);

ALTER TABLE d_entidad_financiera
MODIFY nit VARCHAR(20)
CHARACTER SET utf8mb4
COLLATE utf8mb4_spanish2_ci;

-- Dimensión Personal (Consolida persona, cargo y área)
CREATE TABLE d_personal (
    id_personal INT PRIMARY KEY,
    nombre_completo VARCHAR(200) NOT NULL,
    ci VARCHAR(45),
    cargo VARCHAR(100),
    AREA VARCHAR(100),
    relacion_laboral VARCHAR(50),
    nacionalidad VARCHAR(50)
);

-- TABLAS DE HECHOS 
-- Compras y Crédito Fiscal 
CREATE TABLE fact_compras (
    id_fact_compra INT AUTO_INCREMENT PRIMARY KEY,
    id_compra_oltp INT NOT NULL,
    id_fecha INT NOT NULL,
    id_empresa INT NOT NULL,
    id_proveedor INT NOT NULL,
    id_cuenta INT,
    total_factura DECIMAL(18,2) NOT NULL,
    total_ice DECIMAL(18,2) DEFAULT 0.00,
    importe_exento DECIMAL(18,2) DEFAULT 0.00,
    importe_neto DECIMAL(18,2) NOT NULL,
    credito_fiscal DECIMAL(18,2) NOT NULL,
    descuentos DECIMAL(18,2) DEFAULT 0.00,
    FOREIGN KEY (id_fecha) REFERENCES d_tiempo(id_fecha),
    FOREIGN KEY (id_empresa) REFERENCES d_empresa(id_empresa),
    FOREIGN KEY (id_proveedor) REFERENCES d_proveedor(id_proveedor),
    FOREIGN KEY (id_cuenta) REFERENCES d_cuenta_contable(id_cuenta)
);

-- Transacciones de Bancarización 
CREATE TABLE fact_bancarizacion (
    id_fact_bancarizacion INT AUTO_INCREMENT PRIMARY KEY,
    id_detalle_oltp INT NOT NULL,
    id_fecha INT NOT NULL,
    id_empresa INT NOT NULL,
    id_entidad INT,
    monto_percibido DECIMAL(18,2) DEFAULT 0.00,
    tipo_transaccion VARCHAR(10),
    forma_pago VARCHAR(10),
    es_excluido TINYINT(1) DEFAULT 0,
    FOREIGN KEY (id_fecha) REFERENCES d_tiempo(id_fecha),
    FOREIGN KEY (id_empresa) REFERENCES d_empresa(id_empresa),
    FOREIGN KEY (id_entidad) REFERENCES d_entidad_financiera(id_entidad)
);

-- Control Fiscal, Ventas y Saldos Mensuales 
CREATE TABLE fact_control_fiscal_ventas (
    id_fact_control INT AUTO_INCREMENT PRIMARY KEY,
    id_registro_oltp BIGINT NOT NULL,
    id_fecha INT NOT NULL,
    id_empresa INT NOT NULL,
    id_personal INT,
    total_ventas DECIMAL(18,5) DEFAULT 0.00000,
    total_compras DECIMAL(18,5) DEFAULT 0.00000,
    monto_iva DECIMAL(18,5) DEFAULT 0.00000,
    monto_it DECIMAL(18,5) DEFAULT 0.00000,
    saldo_iva DECIMAL(18,5) DEFAULT 0.00000,
    saldo_iue DECIMAL(18,5) DEFAULT 0.00000,
    monto_comision DECIMAL(18,5) DEFAULT 0.00000,
    monto_total DECIMAL(18,5) DEFAULT 0.00000,
    estado_registro VARCHAR(50),
    FOREIGN KEY (id_fecha) REFERENCES d_tiempo(id_fecha),
    FOREIGN KEY (id_empresa) REFERENCES d_empresa(id_empresa),
    FOREIGN KEY (id_personal) REFERENCES d_personal(id_personal)
); 
