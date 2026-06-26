# Pizzería Online — Infraestructura (Terraform + AWS)

Infraestructura como código (IaC) de la **Pizzería Online** (Grupo 2): 3 microservicios
NestJS comunicados por **NATS**, corriendo en **ECS Fargate**, con base de datos
**DynamoDB** y acceso por **mínimo privilegio** vía IAM. Todo con Terraform.

> Este repo es **solo la infraestructura**. El código de los microservicios vive en el
> repo del backend. Acá se crean los "envases vacíos" (red, cluster, tablas, repos de
> imagen); el backend se conecta a ellos cuando se suben las imágenes Docker a ECR.

## Microservicios

| Servicio | Rol | Tráfico | Tabla(s) DynamoDB (RW) |
|---|---|---|---|
| **orders**   | API HTTP detrás del ALB (única puerta pública). CRUD de pedidos. | HTTP :3000 | `pizzeria-pedidos` |
| **kitchen**  | Worker NATS. Valida stock, simula preparación. | solo NATS | `pizzeria-productos`, `pizzeria-ingredientes` |
| **delivery** | Worker NATS. Asigna repartidor. | solo NATS | `pizzeria-repartidores` |

**Modelo database-per-service ESTRICTO:** cada servicio accede SOLO a sus tablas. Si
necesita datos de otro dominio, los pide por NATS (no toca la tabla ajena). Esto se
fuerza con un **task role de IAM por servicio**, cada uno scopeado al ARN exacto de sus
tablas.

## Arquitectura desplegada

```
                            Internet
                                │
                                ▼
                  ┌──────────────────────────┐
                  │  Application Load        │  ← público (puerto 80)
                  │  Balancer (ALB)          │
                  └────────────┬─────────────┘
                               │ :3000
                               ▼
   ┌─────────────────────────────────────────────────────────┐
   │                  VPC 10.0.0.0/16                          │
   │   Subnet pública AZ-a            Subnet pública AZ-b      │
   │                                                           │
   │      ┌──────────────┐                                     │
   │      │ orders task  │──┐  (HTTP detrás del ALB)           │
   │      └──────────────┘  │                                  │
   │      ┌──────────────┐  │                                  │
   │      │ kitchen task │──┼──► NATS (nats.app.internal:4222) │
   │      └──────────────┘  │         ▲                        │
   │      ┌──────────────┐  │         │                        │
   │      │ delivery task│──┘         │                        │
   │      └──────┬───────┘     ┌──────┴───────┐                │
   │             │             │  NATS task   │                │
   │             │             │  (Fargate)   │                │
   │             │             └──────────────┘                │
   └─────────────┼─────────────────────────────────────────────┘
                 │ (SDK AWS + IAM, NO por la VPC)
                 ▼
        ┌────────────────────────────────────┐
        │  DynamoDB (serverless, fuera de la  │
        │  VPC):  4 tablas PAY_PER_REQUEST    │
        └────────────────────────────────────┘
                 │
                 └──► CloudWatch Logs · ECR (orders/kitchen/delivery) · Cloud Map
```

> **DynamoDB NO vive dentro de la VPC** y NO usa Security Group: se alcanza con el SDK de
> AWS (región + nombre de tabla) y se protege con **IAM** (permisos), no con firewall de
> red. Ese es el cambio de modelo clave respecto a una caché tipo ElastiCache.

## Recursos creados (por archivo)

| Archivo | Recursos AWS |
|---|---|
| `1-providers.tf`        | Provider AWS (~> 5.60), tags por defecto (`Project`, `ManagedBy`, `Course`) |
| `2-variables.tf`        | Variables (región, CIDRs, AZs, `task_cpu/memory`, `*_desired_count`, `image_tag`); `project_name = "pizzeria"` |
| `3-network.tf`          | VPC `10.0.0.0/16`, 2 subnets públicas (`10.0.1.0/24`, `10.0.2.0/24`), IGW, route table |
| `4-security_groups.tf`  | SGs: ALB → orders; kitchen y delivery (workers, sin ingress); NATS (acepta orders/kitchen/delivery en :4222) |
| `5-ecr.tf`              | 3 repos ECR (`pizzeria/orders`, `pizzeria/kitchen`, `pizzeria/delivery`) + lifecycle (máx 10 imágenes) |
| `6-iam.tf`              | Execution role + **3 task roles** con políticas DynamoDB scoped (mínimo privilegio) |
| `7-logs.tf`             | 4 log groups CloudWatch (`/ecs/pizzeria/{nats,orders,kitchen,delivery}`, retención 7 días) |
| `8-service_discovery.tf`| Namespace privado `app.internal` + 4 servicios Cloud Map (nats/orders/kitchen/delivery) |
| `9-alb.tf`              | ALB, target group `ip:3000`, listener HTTP:80, health check `/orders/status/healthcheck` (matcher `200-404`) |
| `10-dynamodb.tf`        | **4 tablas DynamoDB** `PAY_PER_REQUEST` (pedidos, productos, ingredientes, repartidores) |
| `11-ecs.tf`             | Cluster, 4 task definitions (NATS + 3 servicios, Fargate 0.25 vCPU / 0.5 GB), 4 services |
| `12-outputs.tf`         | DNS del ALB, nombres de las tablas, URLs de ECR, login command, cluster, namespace |

## Prerrequisitos

- **Terraform ≥ 1.6**
- **AWS CLI** configurada (`aws configure`) — las credenciales NUNCA van en el repo
- **Docker** local para construir y subir imágenes
- Cuenta AWS con límites de Fargate disponibles en la región (`us-east-1`)

## Flujo de despliegue

### 1. Crear la infraestructura

```bash
terraform init      # descarga el provider de AWS (una vez)
terraform validate  # chequea sintaxis (no toca AWS)
terraform plan      # muestra qué se va a crear (se conecta a AWS, no crea nada)
terraform apply     # crea todo de verdad (pide "yes")
```

Al terminar verás los outputs (DNS del ALB, URLs de ECR, nombres de tablas, etc.).

> En este punto los servicios `orders`, `kitchen` y `delivery` arrancan pero **fallan**,
> porque todavía no hay imágenes en ECR. Es esperable: la infra y las imágenes son cosas
> separadas.

### 2. Construir y subir las imágenes

`--platform linux/amd64` es **obligatorio** si construís desde Mac M1/M2 o Windows ARM
(Fargate corre x86_64).

```bash
# Login a ECR (copiá el comando del output `ecr_login_command`)
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Por cada servicio: build + push (ejemplo orders; repetir kitchen y delivery)
docker build --platform linux/amd64 -f apps/orders/Dockerfile -t <ecr_orders_repository_url>:latest .
docker push <ecr_orders_repository_url>:latest
```

### 3. Forzar redeploy de los servicios ECS

```bash
aws ecs update-service --cluster pizzeria-cluster --service orders   --force-new-deployment
aws ecs update-service --cluster pizzeria-cluster --service kitchen  --force-new-deployment
aws ecs update-service --cluster pizzeria-cluster --service delivery --force-new-deployment
```

### 4. Probar y ver logs

```bash
curl http://<alb_dns_name>/...          # endpoint HTTP de orders (según tu API)

aws logs tail /ecs/pizzeria/orders   --follow
aws logs tail /ecs/pizzeria/kitchen  --follow
aws logs tail /ecs/pizzeria/delivery --follow
aws logs tail /ecs/pizzeria/nats     --follow
```

## Limpieza (¡importante para no pagar de más!)

```bash
terraform destroy   # demuele TODO. Pide "yes".
```

> Los repos ECR tienen `force_delete = true`, así que `destroy` los borra aunque tengan
> imágenes. DynamoDB se borra al instante (no hay nodo que apagar como en ElastiCache).

## Estimación de costo (us-east-1, ~24/7)

| Recurso | Cantidad | Costo aprox. mensual |
|---|---|---|
| Fargate (0.25 vCPU + 0.5 GB) | 4 tareas (nats + 3 servicios) | ~$29 |
| ALB | 1 | ~$17 |
| **DynamoDB** (PAY_PER_REQUEST) | 4 tablas | **~$0** en uso de clase (pagás por request) |
| ECR | <1 GB | ~$0.10 |
| CloudWatch Logs | bajo volumen (7 días) | ~$0.50 |
| **Total** | | **~$47/mes** |

Para una clase: levantar antes de la demo y `terraform destroy` al terminar = unos
centavos. Elegir DynamoDB en vez de ElastiCache ahorra el nodo fijo (~$12/mes) y suma
alta disponibilidad Multi-AZ gratis.

## Conceptos clave (para la defensa)

1. **DynamoDB vs ElastiCache:** DynamoDB es serverless, vive FUERA de la VPC y se protege
   con IAM; ElastiCache es un nodo dentro de la VPC protegido con Security Group.
2. **Mínimo privilegio (IAM):** `execution_role` (común, para arrancar tareas) vs
   `task_role` (uno por servicio, scopeado al ARN de sus tablas). orders no puede tocar
   la tabla de kitchen aunque quiera.
3. **database-per-service:** cada servicio dueño de sus tablas; lo ajeno se pide por NATS.
4. **`awsvpc` network mode:** cada tarea Fargate tiene su propia IP → los target groups
   del ALB son `type = "ip"`, no `instance`.
5. **Cloud Map vs ALB:** tráfico este-oeste entre microservicios por DNS interno
   (`nats.app.internal`); el ALB es solo para tráfico norte-sur (internet → orders).
6. **Encadenamiento de SGs:** las reglas referencian otros SGs, no listas de IPs.
7. **Costo/seguridad:** tareas en subnets públicas para evitar el costo de un NAT Gateway.
8. **State remoto (extra):** el `backend "s3"` para compartir el state en equipo con
   locking — pendiente como punto extra.
