# =====================================================================
#  ARCHIVO 2 / 12  ·  variables.tf
# ---------------------------------------------------------------------
#  QUÉ HACE: son las "perillas" ajustables del proyecto. Cada `variable`
#  es un hueco de plantilla con un valor por defecto (`default`).
#  POR QUÉ VA SEGUNDO: el resto de los archivos LEEN estas variables con
#  `var.nombre`. Conviene conocerlas antes de leer todo lo demás.
#  ¿LO CAMBIO? SÍ, varias. Acá es donde adaptás el proyecto a tu caso.
# =====================================================================

variable "aws_region" {
  description = "Región de AWS donde se desplegará todo."
  type        = string
  default     = "us-east-1" # ✅ DEJAR (us-east-1 es la más barata/completa)
}

# --- Credenciales: NO se ponen acá. Se cargan por fuera. ---
# Quedan en `null` por defecto: si usás `aws configure`, Terraform las toma
# de tu PC. Si usás terraform.tfvars, las completás ahí (y ese archivo está
# en .gitignore, así NO se suben a GitHub).
variable "access_key" {
  description = "AWS access key."
  type        = string
  sensitive   = true # oculta el valor en los logs de Terraform
  default     = null
}

variable "secret_key" {
  description = "AWS secret key."
  type        = string
  sensitive   = true
  default     = null
}

variable "project_name" {
  description = "Prefijo para nombrar todos los recursos."
  type        = string
  default     = "test-nest" # 🔧 CAMBIAR a "pizzeria" (o como llamen al grupo).
  #                            Todos los recursos se llamarán pizzeria-vpc, etc.
}

variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC (el rango de IPs de tu red privada)."
  type        = string
  default     = "10.0.0.0/16" # ✅ DEJAR. 10.0.0.0/16 = 65k IPs privadas, sobra.
}

variable "public_subnet_cidrs" {
  description = "CIDRs de las subnets públicas (una por AZ)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"] # ✅ DEJAR. Dos sub-redes.
}

variable "azs" {
  description = "Availability Zones a usar (2 zonas = alta disponibilidad)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"] # ✅ DEJAR (si cambiás region, ajustá).
}

# --- Cuántas copias de cada servicio correr ---
variable "orders_desired_count" {
  description = "Número de tareas Fargate para orders."
  type        = number
  default     = 1 # ✅ 1 alcanza para la demo. Subilo para alta disponibilidad.
}

variable "notifications_desired_count" {
  description = "Número de tareas Fargate para notifications."
  type        = number
  default     = 1
  # 🔧 OJO: vas a renombrar 'notifications' a 'kitchen' y agregar 'delivery'.
  #         Acá necesitarás: kitchen_desired_count y delivery_desired_count.
}

# --- Tamaño de cada contenedor ---
variable "task_cpu" {
  description = "CPU por tarea Fargate (256 = 0.25 vCPU)."
  type        = string
  default     = "256" # ✅ DEJAR. Lo más chico/barato. Combina con memory=512.
}

variable "task_memory" {
  description = "Memoria por tarea Fargate en MB."
  type        = string
  default     = "512" # ✅ DEJAR.
}

variable "image_tag" {
  description = "Tag de las imágenes en ECR."
  type        = string
  default     = "latest" # ✅ DEJAR para la clase. En prod se usa el commit/sha.
}

variable "redis_node_type" {
  description = "Tipo de nodo ElastiCache para Redis."
  type        = string
  default     = "cache.t3.micro"
  # ❌ ELIMINAR: vos usás DynamoDB, no Redis. Esta variable y elasticache.tf
  #    desaparecen. DynamoDB no necesita "tipo de nodo" (es serverless).
}
