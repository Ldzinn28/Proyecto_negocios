import os
import sys

# Configuración de HADOOP_HOME para Windows
os.environ["HADOOP_HOME"] = r"C:\hadoop"
os.environ["PATH"] += os.pathsep + r"C:\hadoop\bin"

from pyspark.sql import SparkSession
from pyspark.sql.functions import from_json, col
from pyspark.sql.types import StructType, StructField, StringType, DoubleType, LongType, IntegerType
from delta import configure_spark_with_delta_pip

# ==============================================================================
# 1. INICIALIZACIÓN DE SPARK CON LIBRERÍAS ALINEADAS A PYSPARK 4.1.1
# ==============================================================================
builder = SparkSession.builder \
    .appName("Kafka Streaming Contable - dyjdb") \
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension") \
    .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")

# Inyección de paquetes para PySpark 4.1.1
spark = configure_spark_with_delta_pip(
    builder,
    extra_packages=[
        "org.apache.spark:spark-sql-kafka-0-10_2.13:4.1.1"  # <--- Versión alineada a PySpark 4.1.1
    ]
).getOrCreate()

spark.sparkContext.setLogLevel("WARN")

# ==============================================================================
# 2. ESQUEMA DEL MENSAJE DE KAFKA
# ==============================================================================
esquema_compra_kafka = StructType([
    StructField("idcompra", LongType(), True),
    StructField("idPuntoVenta", IntegerType(), True),
    StructField("nitProv", LongType(), True),
    StructField("razonSocialProv", StringType(), True),
    StructField("numfact", LongType(), True),
    StructField("fechaProv", StringType(), True),
    StructField("totalFact", DoubleType(), True),
    StructField("importeNeto", DoubleType(), True),
    StructField("creditoFiscal", DoubleType(), True)
])

print("=== Conectando al Cluster de Apache Kafka (localhost:9092) ===")

# ==============================================================================
# 3. LECTURA EN STREAMING DESDE EL TOPIC DE KAFKA
# ==============================================================================
df_kafka_raw = spark.readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "localhost:9092") \
    .option("subscribe", "dyjdb.compras") \
    .option("startingOffsets", "earliest") \
    .load()

# Transformar payload JSON de la columna value de Kafka
df_compras_stream = df_kafka_raw \
    .selectExpr("CAST(value AS STRING) as json_payload") \
    .select(from_json(col("json_payload"), esquema_compra_kafka).alias("data")) \
    .select("data.*")

# ==============================================================================
# 4. ESCRITURA CONTINUA EN DELTA LAKE
# ==============================================================================
query = df_compras_stream.writeStream \
    .format("delta") \
    .outputMode("append") \
    .option("checkpointLocation", "lakehouse/checkpoints/kafka_compras") \
    .start("lakehouse/bronze/kafka_compras")

print("-> Streaming activo. Escuchando eventos en el Topic 'dyjdb.compras'...")

query.awaitTermination()