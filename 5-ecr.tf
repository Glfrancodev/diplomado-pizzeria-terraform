# =====================================================================
#  ARCHIVO 5 / 12  ·  ecr.tf
# ---------------------------------------------------------------------
#  QUÉ HACE: crea los DEPÓSITOS (repositorios) donde se guardan tus
#  imágenes Docker. ECR = "Elastic Container Registry" = el Docker Hub
#  privado de AWS. Uno por microservicio.
#  POR QUÉ VA QUINTO: no depende de la red. Pero ECS (archivo 11) saca
#  las imágenes de acá, así que conviene tenerlo definido antes.
#  ¿LO CAMBIO? SÍ: necesitás UN repo por microservicio → 3 repos.
# =====================================================================

# --- Repo para la imagen de orders ---
resource "aws_ecr_repository" "orders" {
  name                 = "${var.project_name}/orders" # → "pizzeria/orders"
  image_tag_mutability = "MUTABLE"                     # permite re-pushear "latest"
  force_delete         = true                          # destroy borra el repo aunque tenga imágenes

  image_scanning_configuration {
    scan_on_push = true # AWS escanea vulnerabilidades al subir. ✅ DEJAR.
  }
}

# --- Repo para la imagen de kitchen ---
resource "aws_ecr_repository" "kitchen" {
  name                 = "${var.project_name}/kitchen"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# --- Repo para la imagen de delivery ---
resource "aws_ecr_repository" "delivery" {
  name                 = "${var.project_name}/delivery"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# --- Política de "limpieza": no acumular imágenes viejas (cuesta plata) ---
# `locals` = un valor reutilizable. Acá definimos UNA regla y la usamos en los
# dos repos, para no repetir el JSON.
locals {
  ecr_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantener las ultimas 10 imagenes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10 # si hay más de 10, borra las más viejas
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "orders" {
  repository = aws_ecr_repository.orders.name
  policy     = local.ecr_lifecycle_policy
}

resource "aws_ecr_lifecycle_policy" "kitchen" {
  repository = aws_ecr_repository.kitchen.name
  policy     = local.ecr_lifecycle_policy
}

resource "aws_ecr_lifecycle_policy" "delivery" {
  repository = aws_ecr_repository.delivery.name
  policy     = local.ecr_lifecycle_policy
}
