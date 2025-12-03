# --- NETWORK LOAD BALANCER (NLB) ---

# 1. O Load Balancer (Camada 4 - TCP)
resource "aws_lb" "swarm_nlb" {
  name               = "swarm-nlb"
  internal           = false
  load_balancer_type = "network" # <--- MUDANÇA CRUCIAL
  subnets            = module.vpc.public_subnets
  
  enable_cross_zone_load_balancing = true
}

# 2. Target Group (TCP na porta 80)
# O Traefik vai receber conexões na porta 80 (para o desafio HTTP do Let's Encrypt)
resource "aws_lb_target_group" "swarm_tg_80" {
  name     = "swarm-tg-80"
  port     = 80
  protocol = "TCP" # <--- Protocolo TCP puro
  vpc_id   = module.vpc.vpc_id
  
  # Healthcheck simples (TCP handshake)
  health_check {
    protocol = "TCP"
    port     = "traffic-port"
  }
}

# 3. Target Group (TCP na porta 443)
# O tráfego HTTPS passa direto por aqui
resource "aws_lb_target_group" "swarm_tg_443" {
  name     = "swarm-tg-443"
  port     = 443
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    protocol = "TCP"
    port     = "traffic-port"
  }
}

# 4. Listener 80 (Encaminha para TG 80)
resource "aws_lb_listener" "tcp_80" {
  load_balancer_arn = aws_lb.swarm_nlb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.swarm_tg_80.arn
  }
}

# 5. Listener 443 (Encaminha para TG 443)
resource "aws_lb_listener" "tcp_443" {
  load_balancer_arn = aws_lb.swarm_nlb.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.swarm_tg_443.arn
  }
}

# 6. Anexar Managers ao Target Group 80 e 443
# (NLB não tem Security Group próprio antigo, então liberamos direto nas instâncias)

resource "aws_lb_target_group_attachment" "managers_80" {
  for_each         = aws_instance.manager
  target_group_arn = aws_lb_target_group.swarm_tg_80.arn
  target_id        = each.value.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "managers_443" {
  for_each         = aws_instance.manager
  target_group_arn = aws_lb_target_group.swarm_tg_443.arn
  target_id        = each.value.id
  port             = 443
}

# Repita para Workers se quiser que eles também recebam tráfego direto
resource "aws_lb_target_group_attachment" "workers_80" {
  for_each         = aws_instance.worker
  target_group_arn = aws_lb_target_group.swarm_tg_80.arn
  target_id        = each.value.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "workers_443" {
  for_each         = aws_instance.worker
  target_group_arn = aws_lb_target_group.swarm_tg_443.arn
  target_id        = each.value.id
  port             = 443
}

# output "nlb_dns_name" {
#   value = aws_lb.swarm_nlb.dns_name
# }