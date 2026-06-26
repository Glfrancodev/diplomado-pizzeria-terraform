# =====================================================================
#  ARCHIVO 7 / 12  ·  logs.tf
# ---------------------------------------------------------------------
#  QUÉ HACE: crea el "DIARIO" de cada servicio en CloudWatch Logs.
#  Cada contenedor escribe ahí lo que imprime (console.log, errores, etc.).
#  POR QUÉ VA SÉPTIMO: ECS (archivo 11) apunta cada tarea a su log group.
#  Hay que tenerlos creados antes de que las tareas arranquen.
#  ¿LO CAMBIO? SÍ: un log group por microservicio → necesitás 3 (o 4 con NATS).
# =====================================================================

# --- Diario de NATS ---
resource "aws_cloudwatch_log_group" "nats" {
  name              = "/ecs/${var.project_name}/nats" # → /ecs/pizzeria/nats
  retention_in_days = 7                                # borra logs > 7 días (ahorra plata)
}

# --- Diario de orders ---
resource "aws_cloudwatch_log_group" "orders" {
  name              = "/ecs/${var.project_name}/orders"
  retention_in_days = 7
}

# --- Diario de kitchen ---
resource "aws_cloudwatch_log_group" "kitchen" {
  name              = "/ecs/${var.project_name}/kitchen"
  retention_in_days = 7
}

# --- Diario de delivery ---
resource "aws_cloudwatch_log_group" "delivery" {
  name              = "/ecs/${var.project_name}/delivery"
  retention_in_days = 7
}
