# =====================================================================
#  ARCHIVO 6 / 12  ·  iam.tf
# ---------------------------------------------------------------------
#  QUÉ HACE: los CARNETS DE PERMISO. IAM = "Identity and Access
#  Management". Define qué puede hacer cada cosa dentro de AWS.
#  POR QUÉ VA SEXTO: ECS (archivo 11) le asigna estos roles a las tareas.
#  ¿LO CAMBIO? SÍ, y es IMPORTANTE para vos: al usar DynamoDB tenés que
#  AGREGAR "task roles" con permisos de DynamoDB (mínimo privilegio).
#
#  Hay DOS tipos de rol en ECS y conviene no confundirlos:
#    1) EXECUTION ROLE  → permisos para ARRANCAR la tarea (bajar la imagen
#                          de ECR, escribir logs). Lo usa la "infra" de ECS.
#    2) TASK ROLE       → permisos para que TU CÓDIGO use otros servicios
#                          AWS (ej: leer/escribir DynamoDB). Lo usa tu app.
#  La referencia solo trae el EXECUTION ROLE. Vos tenés que sumar TASK ROLES.
# =====================================================================

# --- "Quién puede asumir este rol": solo las tareas de ECS ---
# Un `data` no CREA nada, solo arma un documento (acá, una política de confianza).
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"] # "esto lo usan las tareas ECS"
    }
  }
}

# --- EXECUTION ROLE: el carnet para arrancar cualquier tarea ---
resource "aws_iam_role" "task_execution" {
  name               = "${var.project_name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# Le pega la política oficial de AWS que permite: bajar imágenes de ECR +
# escribir en CloudWatch Logs. Es una política "managed" (la mantiene AWS).
resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =====================================================================
#  TASK ROLES (uno por servicio) — DynamoDB con MÍNIMO PRIVILEGIO
# ---------------------------------------------------------------------
#  Modelo database-per-service ESTRICTO: cada servicio accede SOLO a sus
#  tablas. El `Resource` de cada política apunta al ARN exacto de la tabla,
#  así un servicio NO puede tocar la tabla de otro aunque quiera.
#    orders   → RW pedidos
#    kitchen  → RW productos + RW ingredientes
#    delivery → RW repartidores
#  Los 3 roles usan la MISMA política de confianza (ecs_tasks_assume): solo
#  las tareas de ECS pueden "ponerse" este carnet.
# =====================================================================

# Acciones de lectura+escritura sobre una tabla DynamoDB. Se define una sola
# vez acá y se reutiliza en las 3 políticas (no repetir la lista a mano).
locals {
  dynamodb_rw_actions = [
    "dynamodb:GetItem",
    "dynamodb:PutItem",
    "dynamodb:UpdateItem",
    "dynamodb:DeleteItem",
    "dynamodb:Query",
    "dynamodb:Scan",
  ]
}

# --- orders: RW SOLO sobre la tabla de pedidos ---
resource "aws_iam_role" "orders_task" {
  name               = "${var.project_name}-orders-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "orders_dynamo" {
  name = "${var.project_name}-orders-dynamo"
  role = aws_iam_role.orders_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = local.dynamodb_rw_actions
      Resource = [aws_dynamodb_table.pedidos.arn]
    }]
  })
}

# --- kitchen: RW sobre productos e ingredientes (es dueño de ambas) ---
resource "aws_iam_role" "kitchen_task" {
  name               = "${var.project_name}-kitchen-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "kitchen_dynamo" {
  name = "${var.project_name}-kitchen-dynamo"
  role = aws_iam_role.kitchen_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = local.dynamodb_rw_actions
      Resource = [
        aws_dynamodb_table.productos.arn,
        aws_dynamodb_table.ingredientes.arn,
      ]
    }]
  })
}

# --- delivery: RW SOLO sobre la tabla de repartidores ---
resource "aws_iam_role" "delivery_task" {
  name               = "${var.project_name}-delivery-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "delivery_dynamo" {
  name = "${var.project_name}-delivery-dynamo"
  role = aws_iam_role.delivery_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = local.dynamodb_rw_actions
      Resource = [aws_dynamodb_table.repartidores.arn]
    }]
  })
}
