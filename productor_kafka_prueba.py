import time
import json
from kafka import KafkaProducer

# Inicializa el productor apuntando al servidor local de Kafka
producer = KafkaProducer(
    bootstrap_servers=['localhost:9092'],
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

print("=== Enviando Eventos de Compras en Tiempo Real a Kafka ===")

# Simulación de transacciones contables en tiempo real
compras_simuladas = [
    {"idcompra": 9001, "idPuntoVenta": 1, "nitProv": 1020435022, "razonSocialProv": "BANCO BCP S.A.", "numfact": 451, "fechaProv": "2026-07-29", "totalFact": 1500.0, "importeNeto": 1500.0, "creditoFiscal": 195.0},
    {"idcompra": 9002, "idPuntoVenta": 2, "nitProv": 1016253021, "razonSocialProv": "ENTEL S.A.", "numfact": 8812, "fechaProv": "2026-07-29", "totalFact": 350.0, "importeNeto": 350.0, "creditoFiscal": 45.5},
]

for compra in compras_simuladas:
    producer.send('dyjdb.compras', value=compra)
    print(f"[OK] Evento enviado a Kafka: Factura N° {compra['numfact']} de {compra['razonSocialProv']}")
    time.sleep(2) # Pausa de 2 segundos entre envíos

producer.flush()
print("=== Simulación completada ===")