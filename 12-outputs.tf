# =====================================================================
#  ARCHIVO 12 / 12  ·  outputs.tf
# ---------------------------------------------------------------------
#  QUÉ HACE: lo que Terraform te IMPRIME al terminar el `apply`. Son los
#  datos útiles que no sabés de antemano (los genera AWS): la URL pública,
#  las URLs de los repos ECR, el endpoint de la base de datos, etc.
#  POR QUÉ VA AL FINAL: solo "lee" cosas ya creadas para mostrártelas.
#  ¿LO CAMBIO? SÍ un poco: el PDF pide como mínimo el DNS del ALB y la URL
#  del frontend como outputs. El de Redis se reemplaza por el de DynamoDB.
# =====================================================================

# --- La URL pública de tu app (la que probás con curl / el frontend) ---
output "alb_dns_name" {
  description = "URL pública del ALB."
  value       = aws_lb.main.dns_name # ✅ OBLIGATORIO según el PDF
}

output "ecr_orders_repository_url" {
  description = "URL del repo ECR para orders."
  value       = aws_ecr_repository.orders.repository_url
}

output "ecr_kitchen_repository_url" {
  description = "URL del repo ECR para kitchen."
  value       = aws_ecr_repository.kitchen.repository_url
}

output "ecr_delivery_repository_url" {
  description = "URL del repo ECR para delivery."
  value       = aws_ecr_repository.delivery.repository_url
}

# --- Comando listo para copiar/pegar y loguear Docker contra ECR ---
output "ecr_login_command" {
  description = "Comando para autenticar Docker contra ECR."
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${local.ecr_registry}"
}

output "cluster_name" {
  description = "Nombre del cluster ECS."
  value       = aws_ecs_cluster.main.name
}

output "service_discovery_namespace" {
  description = "Namespace DNS interno."
  value       = aws_service_discovery_private_dns_namespace.main.name
}

# --- Nombres de las tablas DynamoDB ---
# Reemplazan al viejo output de Redis. Con DynamoDB no hay "endpoint": lo útil
# es ver los nombres reales de las tablas (con el prefijo del proyecto), que es
# lo que tu código recibe por env var.
output "dynamodb_tables" {
  description = "Nombres de las 4 tablas DynamoDB."
  value = {
    pedidos      = aws_dynamodb_table.pedidos.name
    productos    = aws_dynamodb_table.productos.name
    ingredientes = aws_dynamodb_table.ingredientes.name
    repartidores = aws_dynamodb_table.repartidores.name
  }
}

# 🔧 AGREGAR (lo pide el PDF) cuando tengas el frontend:
# output "frontend_url" {
#   description = "URL pública del frontend (S3/CloudFront)."
#   value       = aws_cloudfront_distribution.frontend.domain_name
# }
