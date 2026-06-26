# 🏗️ Guía completa de IaC — Terraform + AWS (Pizzería Online)

> Guía paso a paso para entender al 100% la infraestructura antes de construir.
> Desde lo que se configura UNA sola vez, hasta cómo se crea cada pieza y en qué orden.
> Dividida en 6 etapas: (0) modelo mental · (1) prerrequisitos · (2) cómo piensa Terraform ·
> (3) cada pieza de AWS en orden · (4) el state · (5) la secuencia de comandos · (6) verificación.

---

# Etapa 0 — El modelo mental de Terraform

Tres ideas y ya entendés el 80%:

1. **Declarás el "qué", no el "cómo".** Vos escribís "quiero una VPC, un cluster ECS y 4 tablas".
   Terraform calcula los pasos para crearlo. No le decís *cómo* (no hay clicks ni órdenes paso a paso).

2. **Terraform compara: deseado vs. real.** Cada vez que corrés `apply`, mira (a) lo que pediste
   en los `.tf` y (b) lo que ya existe en AWS, y solo hace **la diferencia**. Si no cambiaste nada,
   no hace nada. Si agregaste una tabla, crea solo esa tabla.

3. **El "state" es la memoria.** Para saber qué ya existe, Terraform guarda un archivo
   `terraform.tfstate` con todo lo que creó. (Etapa 4 lo cubre a fondo.)

```
   tus .tf  ───┐
               ├──► terraform plan ──► "voy a crear X, cambiar Y, borrar Z"
   el state ───┘                              │
                                              ▼
                                       terraform apply ──► AWS
```

---

# Etapa 1 — Lo que configurás UNA sola vez (antes de cualquier Terraform)

Son 5 cosas, en orden:

## 1.1. Cuenta AWS
Necesitás una cuenta de AWS con una tarjeta asociada (aunque casi todo lo del proyecto entra
en free tier o cuesta centavos por horas). Si la facultad da cuentas, usás esa.

## 1.2. Un usuario IAM con permisos + access keys 🔑
**No uses la cuenta "root"** (la del email) para el día a día. Creás un **usuario IAM**:

1. Consola AWS → IAM → Users → Create user (ej: `terraform-deploy`).
2. Le das permisos. Para un proyecto de clase: la política `AdministratorAccess` (Terraform
   necesita crear de todo: VPC, ECS, IAM, DynamoDB…). En producción real se hace scoped,
   pero para aprender, admin está bien.
3. Le generás **Access Keys** (Access Key ID + Secret Access Key). Esas son las "llaves"
   que usará Terraform y el AWS CLI.

> ⚠️ El Secret Access Key se muestra **una sola vez**. Copialo. Si lo perdés, generás otro.

## 1.3. AWS CLI instalado + configurado
Ya lo tenés instalado. Ahora lo configurás con esas llaves:
```bash
aws configure
# AWS Access Key ID:     AKIA....
# AWS Secret Access Key: ....
# Default region name:   us-east-1
# Default output format: json
```
Esto guarda las llaves en `C:\Users\TU_USUARIO\.aws\credentials` (fuera del repo).
Terraform las toma de ahí solo. **Esta es la forma recomendada** (las credenciales nunca
tocan el proyecto → imposible subirlas a GitHub).

Verificás que funciona:
```bash
aws sts get-caller-identity
# Te devuelve tu Account ID y el ARN del usuario. Si esto anda, Terraform va a andar.
```

## 1.4. Terraform y Docker instalados
Ya los tenés (Terraform ≥1.6, Docker corriendo). Docker hace falta recién en el paso de
build/push, no para `terraform apply`.

## 1.5. (Opcional pero recomendado) El bucket para el state remoto
Si tu grupo va a compartir la infra, antes de todo creás **un bucket S3** y **una tabla
DynamoDB de lock**. Esto es lo único que se crea "a mano" porque es el lugar donde vivirá
el state de todo lo demás (problema del huevo y la gallina). Lo vemos en la Etapa 4.

✅ **Con 1.1 a 1.4 ya podés correr Terraform.** El resto es entender qué construye.

---

# Etapa 2 — Cómo Terraform decide el orden (el grafo)

Vos NO ordenás los recursos. Terraform lee **todos** los `.tf` y arma un **grafo de
dependencias** mirando las referencias entre recursos:

```hcl
resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id   # ← esto dice "la subnet necesita la VPC primero"
}
```

Esa línea `aws_vpc.main.id` le dice a Terraform: "creá la VPC, después la subnet". Así
descubre solo todo el orden. Por eso el nombre de los archivos no importa: lo que importa
son las **referencias**.

Terraform además **paraleliza** lo que no depende entre sí (crea ECR y los logs al mismo
tiempo, porque no se necesitan mutuamente).

---

# Etapa 3 — Cada pieza de AWS, en orden de dependencia

El corazón de "entender todo". De los cimientos hacia arriba. Para cada una: **qué es**,
**por qué la necesitás**, **de qué depende**.

## 🌐 Nivel 1 — La red (lo primero que existe)
| Pieza | Qué es | Depende de |
|---|---|---|
| **VPC** | Tu red privada aislada dentro de AWS (un terreno cercado). Todo vive adentro. | nada |
| **Internet Gateway** | La puerta entre tu VPC e internet. | VPC |
| **Subnets** (×2) | Barrios dentro del terreno, en 2 zonas distintas (alta disponibilidad). | VPC |
| **Route table** + asociaciones | El GPS: "para ir a internet, salí por el IGW". | VPC, IGW, subnets |

> Sin la red, nada más se puede crear. Es el cimiento absoluto.

## 🔐 Nivel 2 — Seguridad y permisos (independientes entre sí)
| Pieza | Qué es | Depende de |
|---|---|---|
| **Security Groups** | Firewalls: quién habla con quién y por qué puerto. | VPC |
| **IAM roles** | Carnets de permiso. *Execution role* (arrancar tareas) + *Task roles* (tu código accede a DynamoDB). | nada |

> Estos dos definen **permisos**. Hay dos mundos de permisos:
> - **Red** (Security Groups): controla *conexiones* (puerto 4222 de NATS, etc.).
> - **Identidad** (IAM): controla *acciones en la API de AWS* (leer una tabla DynamoDB).
> DynamoDB se protege con IAM, no con SG. ElastiCache era al revés (SG).
>
> **Cada servicio tiene su PROPIO task role, scopeado solo a SU tabla** (database-per-service
> estricto): orders → RW solo `pedidos`; kitchen → RW `productos` + `ingredientes`;
> delivery → RW `repartidores`. orders no accede a tablas ajenas: pide esos datos a kitchen
> por NATS. Ver detalle del modelo en NOTAS-PROYECTO.md.

## 📦 Nivel 3 — Registros y almacenamiento (independientes)
| Pieza | Qué es | Depende de |
|---|---|---|
| **ECR** (×3 repos) | El depósito de tus imágenes Docker (orders, kitchen, delivery). | nada |
| **DynamoDB** (×4 tablas) | Tu base de datos. Serverless, fuera de la VPC. | nada |
| **CloudWatch Log Groups** (×4) | El **diario** de cada servicio. | nada |

> Los **logs** funcionan así: en la definición de cada tarea ECS le decís "mandá tu salida
> al log group X". El contenedor escribe ahí cada `console.log` y error. Después los ves con
> `aws logs tail /ecs/pizzeria/orders --follow`. Los Log Groups deben existir **antes** de
> que las tareas arranquen, por eso se crean en este nivel.

## 📞 Nivel 4 — Descubrimiento y balanceo
| Pieza | Qué es | Depende de |
|---|---|---|
| **Cloud Map** (namespace + servicios) | La guía telefónica interna: `nats.app.internal`. Para que los servicios se encuentren sin IPs. | VPC |
| **ALB** + target group + listener | El portero público. Recibe internet y reenvía a orders. | VPC, subnets, SG del ALB |

## 🏃 Nivel 5 — La ejecución (depende de CASI TODO)
| Pieza | Qué es | Depende de |
|---|---|---|
| **ECS Cluster** | El predio donde corren los contenedores. | nada |
| **Task Definitions** (×4) | La ficha técnica de cada contenedor: imagen, CPU, variables de entorno, a qué log escribe, qué task role usa. | ECR, IAM, logs, DynamoDB |
| **ECS Services** (×4) | "Mantené N copias vivas siempre". Conecta orders al ALB y registra cada tarea en Cloud Map. | task def, SG, subnets, ALB, Cloud Map |

> Los **servicios** son el nivel más alto: necesitan que TODO lo anterior exista. Por eso
> `ecs.tf` es el último archivo "real" antes de los outputs.

## 📤 Nivel 6 — Outputs
No crean nada. Solo **leen** valores ya creados (el DNS del ALB, las URLs de ECR) y te los
imprimen al terminar.

### El grafo completo, de un vistazo
```
VPC ──► Subnets, IGW, Routes
 │
 ├──► Security Groups ──┐
 ├──► Cloud Map ────────┤
 └──► ALB ──────────────┤
                        ├──► ECS Services ──► (tu app corriendo)
IAM roles ──────────────┤
ECR ────────────────────┤
DynamoDB ───────────────┤
Log Groups ─────────────┘
        (Task Definitions juntan todo esto)
```

---

# Etapa 4 — El state (la pieza que más confunde)

## Qué es
Cuando Terraform crea algo, anota en `terraform.tfstate` (un JSON) el mapeo "este recurso
de mi `.tf` = este recurso real en AWS con este ID". Es su **memoria**.

## Por qué importa
- Sin state, Terraform no sabría qué ya creó → intentaría crear todo de nuevo o no podría borrar.
- El state tiene **datos sensibles** (a veces secretos, endpoints) → por eso está en
  `.gitignore` (`*.tfstate`). **Nunca a GitHub.**

## El problema en equipo
Si vos y un compañero corren `apply` cada uno con su state local → caos (cada uno cree cosas
distintas). Solución: **state remoto en S3 + lock en DynamoDB**.

```hcl
# en providers.tf (hoy está comentado en la plantilla):
terraform {
  backend "s3" {
    bucket         = "pizzeria-tfstate"     # bucket S3 compartido
    key            = "infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "pizzeria-tflock"      # candado: evita 2 apply simultáneos
  }
}
```

El bucket y la tabla de lock son lo único que creás **antes** y a mano (porque son el lugar
donde vivirá el state). Esto vale **puntos extra** del PDF.

---

# Etapa 5 — La secuencia real, paso a paso

Una vez configurado todo lo de la Etapa 1:

```bash
# 1. entrar a la carpeta de infra
cd terraform/option-b-ecs

# 2. inicializar: descarga el provider de AWS y configura el backend.
#    Se corre una vez (o cuando agregás un provider nuevo).
terraform init

# 3. (opcional pero recomendado) validar y formatear
terraform validate     # ¿la sintaxis está bien?
terraform fmt          # ordena la indentación

# 4. VER qué va a hacer, SIN hacerlo. Tu red de seguridad.
terraform plan
#    Lee esto con atención: "Plan: 30 to add, 0 to change, 0 to destroy".
#    Si ves "destroy" inesperado, frená.

# 5. CREAR de verdad. Te pide escribir "yes".
terraform apply
#    Tarda ~10-15 min la 1ra vez (DynamoDB es rápido; antes ElastiCache era lo lento).

# 6. ver los resultados (DNS del ALB, URLs de ECR)
terraform output
```

Después de esto, la infra existe pero **los contenedores fallan** porque todavía no subiste
tus imágenes a ECR. Ese es el paso de Docker (build + push) que hace `deploy.sh` o el CI/CD.
La infra y las imágenes son dos cosas separadas.

---

# Etapa 6 — Cómo verificás que quedó bien

```bash
# ¿los servicios ECS están corriendo? (runningCount debe igualar desiredCount)
aws ecs describe-services --cluster pizzeria-cluster --services orders kitchen delivery \
  --query "services[].{name:serviceName,running:runningCount,desired:desiredCount}"

# ¿qué dicen los logs? (acá ves los console.log de tu app)
aws logs tail /ecs/pizzeria/orders --follow

# ¿responde la app por internet?
curl http://<alb_dns_name>/products
```

Y al terminar la clase, **siempre**:
```bash
terraform destroy     # demuele todo, dejás de pagar. Te pide "yes".
```

---

# Resumen ejecutivo (el orden de "construir" el IaC)

| Etapa | Qué hacés | ¿Cuántas veces? |
|---|---|---|
| **Pre** | Cuenta AWS + usuario IAM + access keys + `aws configure` | Una vez |
| **Pre** | (opcional) bucket S3 + tabla lock para state remoto | Una vez |
| **Build** | Adaptás los `.tf` (DynamoDB, 3er servicio, renombres) | Una vez (el grueso) |
| **Run** | `init` → `plan` → `apply` | Cada cambio de infra |
| **Deploy** | build + push de imágenes + redeploy (deploy.sh / CI/CD) | Cada cambio de código |
| **Verify** | `describe-services`, `logs tail`, `curl` | Cuando quieras |
| **Teardown** | `terraform destroy` | Al terminar |
