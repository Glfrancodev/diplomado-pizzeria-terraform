# =====================================================================
#  ARCHIVO 4 / 12  ·  security_groups.tf
# ---------------------------------------------------------------------
#  QUÉ HACE: los GUARDIAS / firewall. Cada Security Group (SG) decide
#  quién puede hablar con quién y por qué puerto. "ingress" = quién entra,
#  "egress" = a dónde puede salir.
#  POR QUÉ VA CUARTO: necesita la VPC (archivo 3), y casi todo lo de
#  después (ALB, ECS, base de datos) se "enchufa" a uno de estos SGs.
#  ¿LO CAMBIO? SÍ, BASTANTE. Acá aplicás "mínimo privilegio" a TU flujo.
#  Es uno de los archivos que más se evalúa en el rubric.
#
#  CADENA EN LA REFERENCIA:  internet → ALB → orders → {nats, redis}
#                                                       notifications → nats
#  CADENA EN TU PROYECTO:    internet → ALB → orders → nats
#                                              kitchen  → nats
#                                              delivery → nats
#                            (Redis se va; DynamoDB NO usa SG, usa IAM)
# =====================================================================

# --- SG del ALB: deja entrar internet por el puerto 80 ---
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Permite HTTP entrante desde internet hacia el ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP desde internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 0.0.0.0/0 = "desde cualquier IP del mundo"
    # 🔧 Si agregás HTTPS (puntos extra), acá sumás otro ingress en el 443.
  }

  egress { # puede salir a cualquier lado (necesario para reenviar al backend)
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # -1 = todos los protocolos
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# --- SG de orders: SOLO acepta tráfico DESDE el ALB, en el 3000 ---
resource "aws_security_group" "orders" {
  name        = "${var.project_name}-orders-sg"
  description = "Permite trafico solo desde el ALB hacia orders:3000"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP desde ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # ← la clave del mínimo privilegio:
    #   no abre el 3000 a internet, solo al SG del ALB. Nadie más puede entrar.
  }

  egress { # orders sale hacia NATS y hacia DynamoDB (API de AWS por internet)
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-orders-sg" }
}

# --- SG de notifications: NO acepta nada entrante (es worker NATS puro) ---
# 🔧 RENOMBRAR a "kitchen". Tu kitchen es igual: sin ingress, solo egress.
resource "aws_security_group" "notifications" {
  name        = "${var.project_name}-notifications-sg"
  description = "notifications no acepta entrante (microservicio NATS puro)"
  vpc_id      = aws_vpc.main.id

  # (no hay ingress = nadie puede iniciarle conexión. Perfecto para un worker.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-notifications-sg" }
}

# 🔧 AGREGAR: un SG idéntico a este para "delivery" (tu 3er servicio).
#    Copiá este bloque, cambiá "notifications" por "delivery".

# --- SG de NATS: el broker. Solo deja entrar a los servicios, nunca a internet ---
resource "aws_security_group" "nats" {
  name        = "${var.project_name}-nats-sg"
  description = "Broker NATS: ingreso solo desde orders y notifications"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-nats-sg" }
}

# --- Reglas de ingreso a NATS, SEPARADAS del SG de arriba ---
# Se hacen aparte para evitar "dependencias circulares" (orders necesita a NATS
# y NATS necesita a orders → Terraform se marearía si estuviera todo junto).
resource "aws_vpc_security_group_ingress_rule" "nats_from_orders" {
  security_group_id            = aws_security_group.nats.id
  referenced_security_group_id = aws_security_group.orders.id # "dejá entrar a orders"
  ip_protocol                  = "tcp"
  from_port                    = 4222 # puerto de NATS
  to_port                      = 4222
  description                  = "NATS desde orders"
}

resource "aws_vpc_security_group_ingress_rule" "nats_from_notifications" {
  security_group_id            = aws_security_group.nats.id
  referenced_security_group_id = aws_security_group.notifications.id
  ip_protocol                  = "tcp"
  from_port                    = 4222
  to_port                      = 4222
  description                  = "NATS desde notifications"
  # 🔧 RENOMBRAR a kitchen, y AGREGAR una regla igual "nats_from_delivery".
  #    NATS debe aceptar a los 3: orders, kitchen y delivery.
}

# --- SG de Redis (ElastiCache) ---
# ❌ ELIMINAR TODO ESTO. DynamoDB NO vive en la VPC y NO usa Security Group:
#    se protege con IAM (permisos), no con firewall de red. Este es el gran
#    cambio de modelo al pasar de ElastiCache a DynamoDB.
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "ElastiCache Redis: ingreso solo desde orders"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project_name}-redis-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_orders" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = aws_security_group.orders.id
  ip_protocol                  = "tcp"
  from_port                    = 6379 # puerto de Redis
  to_port                      = 6379
  description                  = "Redis desde orders"
}
