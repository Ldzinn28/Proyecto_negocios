import os
from pyspark.sql import SparkSession
from delta import configure_spark_with_delta_pip

builder = SparkSession.builder \
    .appName("Verificar Kafka Delta") \
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension") \
    .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")

spark = configure_spark_with_delta_pip(builder).getOrCreate()

# Leer la capa Bronze donde Kafka insertó los datos
df_kafka_compras = spark.read.format("delta").load("lakehouse/bronze/kafka_compras")

print("\n=== COMPRAS INGRESADAS EN TIEMPO REAL VÍA KAFKA ===")
df_kafka_compras.show(truncate=False)