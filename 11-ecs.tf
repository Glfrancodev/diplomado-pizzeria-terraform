# =====================================================================
#  ARCHIVO 11 / 12  ·  ecs.tf   ← EL MÁS IMPORTANTE / DENSO
# ---------------------------------------------------------------------
#  QUÉ HACE: pone a CORRER los contenedores. ECS Fargate = "ejecutá mis
#  imágenes Docker sin que yo administre servidores".
#  POR QUÉ VA ÚLTIMO (antes de outputs): depende de CASI TODO lo anterior
#  (red, SGs, ECR, IAM, logs, Cloud Map, ALB, base de datos).
#  ¿LO CAMBIO? SÍ, MUCHO. Acá replicás el patrón para tus 3 servicios.
#
#  TRES CONCEPTOS:
#   1) CLUSTER          = el "predio" donde corren las tareas.
#   2) TASK DEFINITION  = la "ficha técnica" de un contenedor (imagen, CPU,
#                          variables de entorno, a qué log escribe).
#   3) SERVICE          = "mantené N copias de esta tarea vivas siempre".
# =====================================================================

# --- 1) El cluster: el predio que agrupa todo ---
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled" # métricas extra de AWS (cuestan). DEJAR en disabled para la clase.
  }
}

# --- Datos y valores calculados que se usan más abajo ---
data "aws_caller_identity" "current" {} # averigua tu account_id de AWS

locals {
  account_id          = data.aws_caller_identity.current.account_id
  ecr_registry        = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  orders_image   = "${aws_ecr_repository.orders.repository_url}:${var.image_tag}"
  kitchen_image  = "${aws_ecr_repository.kitchen.repository_url}:${var.image_tag}"
  delivery_image = "${aws_ecr_repository.delivery.repository_url}:${var.image_tag}"

  # URL interna de NATS, vía Cloud Map (nombre, NO IP). 🔧 esto se queda igual.
  nats_dns_url = "nats://nats.${aws_service_discovery_private_dns_namespace.main.name}:4222"

  # NOTA: el local redis_url se eliminó. Con DynamoDB no hay "URL de base de
  # datos": tu código la alcanza con el SDK de AWS usando región + IAM, y solo
  # necesita los NOMBRES de tabla (que pasamos como env vars más abajo).
}

# --- 2) Task definition de NATS (el broker) ---
resource "aws_ecs_task_definition" "nats" {
  family                   = "${var.project_name}-nats"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  network_mode             = "awsvpc"               # cada tarea con su propia IP en la VPC
  requires_compatibilities = ["FARGATE"]            # serverless (sin EC2)
  execution_role_arn       = aws_iam_role.task_execution.arn # carnet para arrancar

  # La "ficha" del contenedor, en JSON. jsonencode convierte HCL → JSON.
  container_definitions = jsonencode([{
    name      = "nats"
    image     = "nats:2.10-alpine" # imagen oficial (no la tuya). DEJAR.
    essential = true
    command   = ["-js", "-m", "8222"] # arranca NATS con JetStream + monitoreo
    portMappings = [
      { containerPort = 4222, protocol = "tcp" }, # puerto de clientes
      { containerPort = 8222, protocol = "tcp" }  # puerto de monitoreo
    ]
    logConfiguration = {
      logDriver = "awslogs" # manda los logs a CloudWatch
      options = {
        awslogs-group         = aws_cloudwatch_log_group.nats.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "nats"
      }
    }
  }])
}

# --- Task definition de orders (TU servicio HTTP) ---
resource "aws_ecs_task_definition" "orders" {
  family                   = "${var.project_name}-orders"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.task_execution.arn      # arrancar la tarea
  task_role_arn            = aws_iam_role.orders_task.arn         # permisos DynamoDB (pedidos)

  container_definitions = jsonencode([{
    name      = "orders"
    image     = local.orders_image # tu imagen subida a ECR
    essential = true
    portMappings = [
      { containerPort = 3000, protocol = "tcp" }
    ]
    # Variables de entorno que recibe tu app NestJS:
    environment = [
      { name = "NATS_URL", value = local.nats_dns_url }, # ✅ se queda
      { name = "ORDERS_HTTP_PORT", value = "3000" },
      # DynamoDB: orders es dueño SOLO de pedidos. La región la necesita el SDK
      # de AWS; el nombre de la tabla llega por env var (no se hardcodea).
      { name = "AWS_REGION", value = var.aws_region },
      { name = "TABLE_PEDIDOS", value = aws_dynamodb_table.pedidos.name }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.orders.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "orders"
      }
    }
  }])
}

# --- Task definition de kitchen (worker NATS) ---
# kitchen es dueño de productos e ingredientes. El task_role con permisos
# DynamoDB se asigna en el siguiente paso (requisito #2).
resource "aws_ecs_task_definition" "kitchen" {
  family                   = "${var.project_name}-kitchen"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.task_execution.arn      # arrancar la tarea
  task_role_arn            = aws_iam_role.kitchen_task.arn        # permisos DynamoDB (productos + ingredientes)

  container_definitions = jsonencode([{
    name      = "kitchen"
    image     = local.kitchen_image
    essential = true
    # (sin portMappings: es un worker, nadie le hace requests HTTP)
    environment = [
      { name = "NATS_URL", value = local.nats_dns_url },
      { name = "AWS_REGION", value = var.aws_region },
      { name = "TABLE_PRODUCTOS", value = aws_dynamodb_table.productos.name },
      { name = "TABLE_INGREDIENTES", value = aws_dynamodb_table.ingredientes.name }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.kitchen.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "kitchen"
      }
    }
  }])
}

# --- Task definition de delivery (worker NATS) ---
# delivery es dueño de repartidores. Su task_role se asigna en el requisito #2.
resource "aws_ecs_task_definition" "delivery" {
  family                   = "${var.project_name}-delivery"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.task_execution.arn      # arrancar la tarea
  task_role_arn            = aws_iam_role.delivery_task.arn       # permisos DynamoDB (repartidores)

  container_definitions = jsonencode([{
    name      = "delivery"
    image     = local.delivery_image
    essential = true
    environment = [
      { name = "NATS_URL", value = local.nats_dns_url },
      { name = "AWS_REGION", value = var.aws_region },
      { name = "TABLE_REPARTIDORES", value = aws_dynamodb_table.repartidores.name }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.delivery.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "delivery"
      }
    }
  }])
}

# --- 3) Service de NATS: "mantené 1 NATS vivo siempre" ---
resource "aws_ecs_service" "nats" {
  name            = "nats"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.nats.arn
  desired_count   = 1 # cuántas copias
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.nats.id]
    assign_public_ip = true # IP pública (porque no usamos NAT Gateway)
  }

  # Registra la tarea en la guía telefónica (Cloud Map) → nats.app.internal
  service_registries {
    registry_arn = aws_service_discovery_service.nats.arn
  }
}

# --- Service de orders: lo conecta al ALB ---
resource "aws_ecs_service" "orders" {
  name            = "orders"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.orders.arn
  desired_count   = var.orders_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.orders.id]
    assign_public_ip = true
  }

  # ESTO es lo que enchufa orders al balanceador (el ALB le manda tráfico).
  load_balancer {
    target_group_arn = aws_lb_target_group.orders.arn
    container_name   = "orders"
    container_port   = 3000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.orders.arn
  }

  depends_on = [aws_lb_listener.http] # esperá a que el listener exista
}

# --- Service de kitchen (worker: SIN load_balancer, no va detrás del ALB) ---
resource "aws_ecs_service" "kitchen" {
  name            = "kitchen"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.kitchen.arn
  desired_count   = var.kitchen_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.kitchen.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.kitchen.arn
  }
}

# --- Service de delivery (worker: SIN load_balancer) ---
resource "aws_ecs_service" "delivery" {
  name            = "delivery"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.delivery.arn
  desired_count   = var.delivery_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.delivery.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.delivery.arn
  }
}
