# =====================================================================
#  ARCHIVO 3 / 12  ·  network.tf
# ---------------------------------------------------------------------
#  QUÉ HACE: construye la RED. El "terreno y las calles" donde vivirá
#  todo lo demás: tu red privada (VPC), los barrios (subnets) y la
#  carretera a internet (Internet Gateway + tabla de rutas).
#  POR QUÉ VA TERCERO: casi TODO lo demás (servidores, base de datos,
#  balanceador) necesita estar "dentro" de esta red. Es la base física.
#  ¿LO CAMBIO? Normalmente NO. Esta red sirve igual para cualquier proyecto.
# =====================================================================

# --- La VPC: tu plot de terreno privado dentro de AWS ---
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr # rango de IPs (10.0.0.0/16)
  enable_dns_hostnames = true         # necesario para que Cloud Map funcione
  enable_dns_support   = true         # resolución de nombres internos

  tags = {
    Name = "${var.project_name}-vpc" # → "pizzeria-vpc"
  }
}

# --- Internet Gateway: la puerta/carretera entre tu VPC e internet ---
# Sin esto, nada dentro de la VPC puede salir ni entrar de internet.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id # se engancha a la VPC de arriba

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# --- Subnets públicas: los "barrios" dentro del terreno ---
# `count` crea VARIAS de un saque (una por cada CIDR de la lista).
# Son PÚBLICAS = las tareas reciben IP pública (así evitamos pagar un NAT
# Gateway, que cuesta ~$32/mes). Trade-off: simplicidad vs. aislamiento.
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs) # = 2 subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index] # 10.0.1.0/24, 10.0.2.0/24
  availability_zone       = var.azs[count.index]                # us-east-1a, us-east-1b
  map_public_ip_on_launch = true                                # IP pública automática

  tags = {
    Name = "${var.project_name}-public-${var.azs[count.index]}"
    Tier = "public"
  }
}

# --- Tabla de rutas: el "GPS" que dice cómo salir a internet ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"                     # "cualquier destino (internet)..."
    gateway_id = aws_internet_gateway.main.id    # "...salí por la puerta IGW"
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# --- Conectar cada subnet a esa tabla de rutas ---
# Sin esto, las subnets no sabrían cómo llegar a internet.
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
