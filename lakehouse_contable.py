import os
import sys

# Configuración de HADOOP_HOME (entornos Windows)
os.environ["HADOOP_HOME"] = r"C:\hadoop"
os.environ["PATH"] += os.pathsep + r"C:\hadoop\bin"

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, when, sum, count
from delta import configure_spark_with_delta_pip

# ==============================================================================
# 1. INICIALIZACIÓN DE SPARK + DELTA LAKE + MYSQL
# ==============================================================================
builder = SparkSession.builder \
    .appName("Lakehouse Contable - dyjdb") \
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension") \
    .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")

spark = configure_spark_with_delta_pip(
    builder,
    extra_packages=["com.mysql:mysql-connector-j:9.3.0"]
).getOrCreate()

spark.sparkContext.setLogLevel("WARN")

jdbc_url = "jdbc:mysql://localhost:3306/dyjdb"
properties = {
    "user": "root",
    "password": "root",
    "driver": "com.mysql.cj.jdbc.Driver"
}

print("=== Iniciando Extracción desde MySQL (dyjdb) ===")

# Extracción de tablas origen
compra = spark.read.jdbc(url=jdbc_url, table="compra", properties=properties)
bancarizacion_detalle = spark.read.jdbc(url=jdbc_url, table="bancarizacion_detalle", properties=properties)
seguimiento = spark.read.jdbc(url=jdbc_url, table="seguimiento", properties=properties)
empresa = spark.read.jdbc(url=jdbc_url, table="empresa", properties=properties)
persona = spark.read.jdbc(url=jdbc_url, table="persona", properties=properties)

# ==============================================================================
# 2. CAPA BRONZE (Ingesta cruda en formato Delta)
# ==============================================================================
print("=== Guardando Capa Bronze ===")

compra.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save("lakehouse/bronze/compra")
bancarizacion_detalle.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save("lakehouse/bronze/bancarizacion_detalle")
seguimiento.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save("lakehouse/bronze/seguimiento")
empresa.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save("lakehouse/bronze/empresa")
persona.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save("lakehouse/bronze/persona")

print("-> Capa Bronze guardada con éxito en Parquet/Delta.")

# ==============================================================================
# 3. CAPA SILVER (Limpieza, tratamiento de nulos y casteo)
# ==============================================================================
print("=== Procesando Capa Silver ===")

compra_b = spark.read.format("delta").load("lakehouse/bronze/compra").dropDuplicates(["idcompra"])
banc_b = spark.read.format("delta").load("lakehouse/bronze/bancarizacion_detalle").dropDuplicates(["iddetalle"])
seguimiento_b = spark.read.format("delta").load("lakehouse/bronze/seguimiento").dropDuplicates(["idsgto"])
empresa_b = spark.read.format("delta").load("lakehouse/bronze/empresa").dropDuplicates(["idempresa"])

silver_compras = compra_b \
    .withColumn("totalFact", when(col("totalFact").isNull(), 0.0).otherwise(col("totalFact").cast("double"))) \
    .withColumn("importeNeto", when(col("importeNeto").isNull(), 0.0).otherwise(col("importeNeto").cast("double"))) \
    .withColumn("creditoFiscal", when(col("creditoFiscal").isNull(), 0.0).otherwise(col("creditoFiscal").cast("double")))

silver_bancarizacion = banc_b \
    .withColumn("monto_percibido", when(col("monto_percibido").isNull(), 0.0).otherwise(col("monto_percibido").cast("double"))) \
    .withColumn("excluido", when(col("excluido").isNull(), 0).otherwise(col("excluido").cast("int")))

silver_seguimiento = seguimiento_b \
    .withColumn("ventas", when(col("ventas").isNull(), 0.0).otherwise(col("ventas").cast("double"))) \
    .withColumn("compras", when(col("compras").isNull(), 0.0).otherwise(col("compras").cast("double"))) \
    .withColumn("iva", when(col("iva").isNull(), 0.0).otherwise(col("iva").cast("double"))) \
    .withColumn("it", when(col("it").isNull(), 0.0).otherwise(col("it").cast("double"))) \
    .withColumn("total", when(col("total").isNull(), 0.0).otherwise(col("total").cast("double")))

silver_compras.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save("lakehouse/silver/compras")
silver_bancarizacion.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save("lakehouse/silver/bancarizacion")
silver_seguimiento.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save("lakehouse/silver/control_registros")
empresa_b.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save("lakehouse/silver/empresa")

print("-> Capa Silver procesada y limpia.")

# ==============================================================================
# 4. CAPA GOLD (Agregaciones analíticas R1-R4)
# ==============================================================================
print("=== Generando Tablas Analíticas en Capa Gold ===")

s_compras = spark.read.format("delta").load("lakehouse/silver/compras")
s_banc = spark.read.format("delta").load("lakehouse/silver/bancarizacion")
s_seg = spark.read.format("delta").load("lakehouse/silver/control_registros")
s_empresa = spark.read.format("delta").load("lakehouse/silver/empresa")

# Gold 1 (R1): Resumen de Compras y Crédito Fiscal por Proveedor
gold_compras_proveedor = s_compras.groupBy("nitProv", "razonSocialProv") \
    .agg(
        sum("totalFact").alias("total_compras_facturadas"),
        sum("importeNeto").alias("total_importe_neto"),
        sum("creditoFiscal").alias("total_credito_fiscal"),
        count("idcompra").alias("cantidad_facturas")
    )

# Gold 2 (R2): Montos Bancarizados por Entidad Financiera
gold_bancarizacion_banco = s_banc.groupBy("nit_entidad_financiera") \
    .agg(
        sum("monto_percibido").alias("total_monto_bancarizado"),
        count("iddetalle").alias("total_operaciones")
    )

# Gold 3 (R3 & R4): Consolidado Mensual por Empresa desde Seguimiento
gold_control_empresa = s_seg \
    .join(s_empresa, s_seg.idempresa == s_empresa.idempresa, "left") \
    .groupBy(s_empresa.razonSocial.alias("empresa"), s_seg.ano, s_seg.mes) \
    .agg(
        sum("ventas").alias("total_ventas"),
        sum("compras").alias("total_compras"),
        sum("iva").alias("total_iva"),
        sum("it").alias("total_it"),
        sum("total").alias("monto_total_impuestos")
    )

print("\n--- Vista Previa: Compras por Proveedor (Gold) ---")
gold_compras_proveedor.show(5)

print("\n--- Vista Previa: Control Fiscal por Empresa (Gold) ---")
gold_control_empresa.show(5)

gold_compras_proveedor.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save("lakehouse/gold/compras_por_proveedor")
gold_bancarizacion_banco.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save("lakehouse/gold/bancarizacion_por_banco")
gold_control_empresa.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save("lakehouse/gold/control_por_empresa")

print("\n¡Proceso Delta Lakehouse completado con éxito para la Base de Datos Contable!")