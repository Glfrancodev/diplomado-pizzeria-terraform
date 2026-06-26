# =====================================================================
#  ARCHIVO 10 / 12  ·  dynamodb.tf   ← REEMPLAZA A elasticache.tf
# ---------------------------------------------------------------------
#  QUÉ HACE: crea las 4 tablas de tu base de datos en DynamoDB.
#  DynamoDB es la BD del proyecto (NO Redis/ElastiCache).
#
#  DIFERENCIA CLAVE (gran punto para la presentación):
#    - ElastiCache = un SERVIDOR dentro de la VPC → se protege con Security
#      Group (firewall de red) y necesita subnet group.
#    - DynamoDB = un SERVICIO serverless FUERA de la VPC → se protege con
#      IAM (permisos), no con SG. No tiene "nodos" ni "subnets" ni "URL".
#      Tu código la alcanza con el SDK de AWS usando región + nombre de tabla,
#      y los permisos los da el TASK ROLE de IAM (ver iam.tf).
#
#  MODELO database-per-service ESTRICTO: cada servicio toca SOLO su(s) tabla(s).
#    pedidos      → dueño orders
#    productos    → dueño kitchen
#    ingredientes → dueño kitchen
#    repartidores → dueño delivery
#
#  ¿LO CAMBIO? Acaba de crearse para tu proyecto. Si agregás más tablas,
#  copiás un bloque y le cambiás el name + la hash_key.
# =====================================================================

# --- Tabla de pedidos (dueño: orders) ---
resource "aws_dynamodb_table" "pedidos" {
  name         = "${var.project_name}-pedidos" # → "pizzeria-pedidos"
  billing_mode = "PAY_PER_REQUEST"             # serverless: pagás por uso, sin reservar capacidad
  hash_key     = "pedidoId"                    # partition key (clave primaria)

  # En DynamoDB solo se declaran los atributos que son CLAVE. El resto de los
  # campos (cliente, items, total, estado...) son libres y los maneja el código.
  attribute {
    name = "pedidoId"
    type = "S" # S = String (las otras opciones serían N = número, B = binario)
  }

  tags = { Name = "${var.project_name}-pedidos" }
}

# --- Tabla de productos (dueño: kitchen) ---
resource "aws_dynamodb_table" "productos" {
  name         = "${var.project_name}-productos" # → "pizzeria-productos"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "productoId"

  attribute {
    name = "productoId"
    type = "S"
  }

  tags = { Name = "${var.project_name}-productos" }
}

# --- Tabla de ingredientes (dueño: kitchen) ---
resource "aws_dynamodb_table" "ingredientes" {
  name         = "${var.project_name}-ingredientes" # → "pizzeria-ingredientes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ingredienteId"

  attribute {
    name = "ingredienteId"
    type = "S"
  }

  tags = { Name = "${var.project_name}-ingredientes" }
}

# --- Tabla de repartidores (dueño: delivery) ---
resource "aws_dynamodb_table" "repartidores" {
  name         = "${var.project_name}-repartidores" # → "pizzeria-repartidores"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "repartidorId"

  attribute {
    name = "repartidorId"
    type = "S"
  }

  tags = { Name = "${var.project_name}-repartidores" }
}
