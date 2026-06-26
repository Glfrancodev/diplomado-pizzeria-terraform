# =====================================================================
#  ARCHIVO 9 / 12  ·  alb.tf
# ---------------------------------------------------------------------
#  QUÉ HACE: el PORTERO público (Application Load Balancer). Recibe TODO
#  el tráfico de internet y lo reenvía al servicio HTTP (orders).
#  Es el equivalente a nginx como reverse proxy, pero administrado por AWS.
#  POR QUÉ VA NOVENO: necesita la VPC, las subnets y el SG del ALB.
#  Y ECS (archivo 11) "enchufa" orders a este balanceador.
#  ¿LO CAMBIO? Casi NO. Solo el health check si cambia tu ruta. Si querés
#  HTTPS (puntos extra), agregás un certificado ACM + listener en :443.
#
#  3 PIEZAS:  aws_lb (el portero) → aws_lb_target_group (a quién le paso)
#             → aws_lb_listener (en qué puerto escucho)
# =====================================================================

# --- El balanceador en sí: la puerta pública ---
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false                       # false = público (de cara a internet)
  load_balancer_type = "application"               # "application" = capa 7 (HTTP)
  security_groups    = [aws_security_group.alb.id] # usa el guardia del ALB
  subnets            = aws_subnet.public[*].id     # vive en las 2 subnets públicas
}

# --- Target group: "el grupo de destino" = a quién le mando el tráfico ---
# Apunta a orders en el puerto 3000.
resource "aws_lb_target_group" "orders" {
  name        = "${var.project_name}-orders-tg"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip" # "ip" porque Fargate usa IPs (no instancias EC2)
  vpc_id      = aws_vpc.main.id

  # Health check: el ALB "pincha" esta ruta cada 15s para ver si orders vive.
  # Si responde mal varias veces, deja de mandarle tráfico.
  health_check {
    path                = "/orders/status/healthcheck" # 🔧 ajustá a una ruta REAL de tu API
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200-404" # acepta códigos 200 a 404 como "vivo"
    #   (truco de la referencia: la ruta cae dentro de un GET existente y
    #    devuelve 200, así pasa el health check sin endpoint dedicado.
    #    En tu proyecto podés crear un /health limpio que devuelva 200.)
  }

  deregistration_delay = 10 # segundos de gracia al sacar una tarea
}

# --- Listener: "escucho en el puerto 80 y reenvío al target group" ---
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.orders.arn # todo va a orders
  }
  # 🔧 HTTPS (extra): acá agregarías otro listener en :443 con
  #    ssl_policy + certificate_arn (de un aws_acm_certificate).
}
