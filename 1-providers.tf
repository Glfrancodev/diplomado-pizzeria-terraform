# =====================================================================
#  ARCHIVO 1 / 12  ·  providers.tf
# ---------------------------------------------------------------------
#  QUÉ HACE: define CON QUIÉN habla Terraform (AWS) y con qué versiones.
#  POR QUÉ VA PRIMERO: es el cimiento. Sin saber "vamos a AWS" y con qué
#  credenciales, ningún otro recurso se puede crear.
#  ¿LO CAMBIO? Casi nada. Solo si cambiás de región o de cuenta.
# =====================================================================

terraform {
  # Versión mínima del programa Terraform. Si tu Terraform es más viejo, falla.
  # DEJAR como está (a menos que uses una versión muy vieja).
  required_version = ">= 1.6.0"

  required_providers {
    # El "plugin" que sabe hablar con AWS. Terraform lo descarga en `init`.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60" # ~> 5.60 = cualquier 5.x desde 5.60. DEJAR.
    }
  }
}

# Configuración concreta del proveedor AWS.
provider "aws" {
  region     = var.aws_region # 🔧 viene de variables.tf (default us-east-1)
  access_key = var.access_key # 🔐 viene de terraform.tfvars o `aws configure`
  secret_key = var.secret_key # 🔐 NUNCA se escribe acá directo (iría a Git)

  # Etiquetas que AWS pega AUTOMÁTICAMENTE a TODOS los recursos.
  # Sirve para identificar y para ver costos por proyecto en la factura.
  default_tags {
    tags = {
      Project   = var.project_name # 🔧 cambiá el default en variables.tf
      ManagedBy = "Terraform"
      Course    = "IaC"
    }
  }
}
