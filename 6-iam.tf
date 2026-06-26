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
#  🔧 LO QUE DEBÉS AGREGAR PARA TU PROYECTO (DynamoDB) — esquema:
# ---------------------------------------------------------------------
#  Por cada servicio que toca DynamoDB, creás un TASK ROLE + una política
#  que le da acceso SOLO a sus tablas (mínimo privilegio). Ejemplo orders:
#
#  resource "aws_iam_role" "orders_task" {
#    name               = "${var.project_name}-orders-task"
#    assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
#  }
#
#  resource "aws_iam_role_policy" "orders_dynamo" {
#    role = aws_iam_role.orders_task.id
#    policy = jsonencode({
#      Version = "2012-10-17"
#      Statement = [
#        { # pedidos y productos: lectura + escritura (orders es dueño)
#          Effect   = "Allow"
#          Action   = ["dynamodb:GetItem","dynamodb:PutItem","dynamodb:UpdateItem",
#                      "dynamodb:DeleteItem","dynamodb:Query","dynamodb:Scan"]
#          Resource = [aws_dynamodb_table.pedidos.arn, aws_dynamodb_table.productos.arn]
#        },
#        { # ingredientes: SOLO lectura (orders no es dueño, solo muestra el menú)
#          Effect   = "Allow"
#          Action   = ["dynamodb:GetItem","dynamodb:Query","dynamodb:Scan"]
#          Resource = [aws_dynamodb_table.ingredientes.arn]
#        }
#      ]
#    })
#  }
#
#  Repetís el patrón para kitchen (RW ingredientes, R productos) y delivery
#  (RW repartidores). Después, en ecs.tf, cada task_definition usa su
#  `task_role_arn = aws_iam_role.<servicio>_task.arn`.
#  Así cada servicio toca SOLO sus tablas: mínimo privilegio impecable.
# =====================================================================
