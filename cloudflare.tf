terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }
}


provider "cloudflare" {
  # Opção 1 (Recomendada): Usar variáveis de ambiente.
  # O Terraform busca automaticamente as variáveis CLOUDFLARE_API_TOKEN ou CLOUDFLARE_EMAIL/CLOUDFLARE_API_KEY
  # O bloco abaixo é opcional se as variáveis de ambiente estiverem setadas.
  
  # Opção 2 (Hardcoded - Não recomendado para segredo):
  api_token = "lT2UnDeewkaOKcCpILXbFrRUsOuvNJ6CoMl3ztQs"
}

# # 1. Busca o ID da zona existente
# data "cloudflare_zone" "dominio_swarm" {
#   zone_id = "10d41be99f37eefc51ebb0b4669211d0"
# }

# 2. CRIAR O REGISTRO DNS (CNAME para o NLB)
resource "cloudflare_dns_record" "whoami" {
  # ID da zona obtido no passo anterior
  zone_id = "10d41be99f37eefc51ebb0b4669211d0"
  
  # Nome do subdomínio (ex: 'whoami' resulta em whoami.seudominio.com)
  # O Traefik usará este host para roteamento.
  name    = "haproxy" 
  
  # Tipo de registro (CNAME é usado para apontar para outro domínio, o NLB)
  type    = "A"
  
  # O valor do CNAME é o DNS gerado pelo NLB da AWS
  content = aws_instance.haproxy.public_ip
  
  # Tempo de vida (TTL) em segundos. 1 = Automático no Cloudflare.
  ttl     = 300 
  
  # Ativar o Proxy do Cloudflare (Nuvem Laranja)
  proxied = false 
  
  # Adiciona um comentário para organização
  comment = "CNAME para o NLB do cluster Docker Swarm"
  
  # Campos 'settings' e 'tags' (como definidos no seu bloco) foram removidos, 
  # pois não são atributos válidos para o recurso cloudflare_record.
}