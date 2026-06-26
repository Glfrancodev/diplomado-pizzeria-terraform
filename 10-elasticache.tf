# =====================================================================
#  ARCHIVO 10 / 12  ·  elasticache.tf
# ---------------------------------------------------------------------
#  QUÉ HACE: crea la base de datos Redis ADMINISTRADA (ElastiCache).
#  En la REFERENCIA, orders guarda las órdenes acá.
#
#  ❌❌❌  ESTE ARCHIVO COMPLETO SE ELIMINA EN TU PROYECTO  ❌❌❌
#
#  Vos usás DynamoDB. Tenés que:
#    1) Borrar este archivo (elasticache.tf).
#    2) Borrar el SG de redis en security_groups.tf.
#    3) Borrar la variable redis_node_type en variables.tf.
#    4) Crear un archivo nuevo: dynamodb.tf con tus 4 tablas.
#
#  DIFERENCIA CLAVE (gran punto para tu presentación):
#    - ElastiCache = un SERVIDOR dentro de la VPC → se protege con Security
#      Group (firewall de red) y necesita subnet group.
#    - DynamoDB = un SERVICIO serverless FUERA de la VPC → se protege con
#      IAM (permisos), no con SG. No tiene "nodos" ni "subnets".
#
#  ESQUEMA del dynamodb.tf que vas a crear (una tabla; repetí x4):
#
#    resource "aws_dynamodb_table" "pedidos" {
#      name         = "${var.project_name}-pedidos"
#      billing_mode = "PAY_PER_REQUEST"   # serverless, pagás por uso (lo más barato)
#      hash_key     = "orderId"           # = partition key
#      attribute {
#        name = "orderId"
#        type = "S"                       # S = String (solo se declara la KEY)
#      }
#    }
#    # ...y lo mismo para productos (hash_key productId), ingredientes
#    #    (ingredienteId) y repartidores (repartidorId).
# =====================================================================

# --- Grupo de subnets para Redis (en qué subnets puede vivir el nodo) ---
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-redis-subnets"
  subnet_ids = aws_subnet.public[*].id
}

# --- El nodo Redis administrado ---
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.redis_node_type # cache.t3.micro (el más chico)
  num_cache_nodes      = 1                   # 1 nodo (sin réplica)
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id] # ← protegido por SG (red)
}
