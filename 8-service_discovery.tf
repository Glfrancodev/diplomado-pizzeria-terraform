# =====================================================================
#  ARCHIVO 8 / 12  ·  service_discovery.tf
# ---------------------------------------------------------------------
#  QUÉ HACE: la GUÍA TELEFÓNICA interna (AWS Cloud Map). Le da a cada
#  servicio un nombre DNS interno (ej: nats.app.internal) para que se
#  encuentren entre ellos SIN usar IPs (las IPs cambian cada vez que una
#  tarea reinicia; los nombres no).
#  POR QUÉ VA OCTAVO: necesita la VPC. ECS (archivo 11) registra cada
#  tarea en una de estas "entradas" de la guía.
#  ¿LO CAMBIO? SÍ: una entrada por servicio → necesitás orders, kitchen,
#  delivery y nats. (Como DynamoDB no vive en la VPC, NO se registra acá:
#  se accede por su endpoint público de AWS, no por DNS interno.)
# =====================================================================

# --- El "namespace": el apellido común de todos. Ej: *.app.internal ---
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "app.internal" # ✅ DEJAR. Resulta en nats.app.internal, etc.
  description = "Namespace privado para service discovery interno"
  vpc         = aws_vpc.main.id # privado: solo resuelve DENTRO de tu VPC
}

# --- Entrada para NATS → nats.app.internal ---
resource "aws_service_discovery_service" "nats" {
  name = "nats"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10  # segundos que se "cachea" la IP. Bajo = reacciona rápido a cambios.
      type = "A" # registro A = nombre → IP
    }
    routing_policy = "MULTIVALUE" # si hay varias tareas, devuelve varias IPs
  }

  health_check_custom_config {
    failure_threshold = 1 # ECS marca la tarea como sana/no-sana
  }
}

# --- Entrada para orders → orders.app.internal ---
resource "aws_service_discovery_service" "orders" {
  name = "orders"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# --- Entrada para notifications → notifications.app.internal ---
# 🔧 RENOMBRAR a "kitchen" y AGREGAR una entrada igual para "delivery".
resource "aws_service_discovery_service" "notifications" {
  name = "notifications"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
