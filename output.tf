## 🚀 OUTPUTS ESSENCIAIS PARA USO E DEBUG

# 1. IP Público do haproxy Host
# Usado para acesso manual via SSH
output "haproxy_ip" {
  description = "IP Público do haproxy Host para acesso SSH na porta 60022."
  value       = aws_instance.haproxy.public_ip
}

# # 2. DNS do Network Load Balancer (NLB)
# # Usado para configurar o CNAME no Cloudflare
# output "nlb_dns_name" {
#   description = "DNS Name do Network Load Balancer (NLB) para Ingress."
#   value       = aws_lb.swarm_nlb.dns_name
# }

# 3. IPs Privados dos Managers
# Usado para debug e comandos internos do cluster
output "manager_private_ips" {
  description = "Lista de IPs privados dos nós Manager."
  value       = values(aws_instance.manager)[*].private_ip
}

# 4. Comando SSH de Acesso (Exemplo)
# Facilita o acesso rápido ao haproxy
output "ssh_haproxy_command" {
  description = "Comando SSH para acesso ao haproxy Host."
  value       = "ssh -i chave-cazia.pem -p 60022 ubuntu@${aws_instance.haproxy.public_ip}"
}

output "ssh_manager_01_proxy_command" {
  description = "Comando para SSH no PRIMEIRO MANAGER (Master) via haproxy Host Proxy."
  value = format(
    "ssh -i chave-cazia.pem -o ProxyCommand=\"ssh -W %%h:%%p -i chave-cazia.pem -p 60022 ubuntu@%s\" ubuntu@%s",
    aws_instance.haproxy.public_ip, # IP Público do haproxy
    values(aws_instance.manager)[0].private_ip # IP Privado do Manager
  )
}

output "ssh_config_proxy_block" {
  description = "Bloco de configuração SSH para acesso aos nós privados via haproxy."
  value = <<-EOT
# --- INÍCIO: CONFIGURAÇÃO CAZIA SWARM ---
# 1. Configuração do haproxy Host
Host haproxy
    HostName ${aws_instance.haproxy.public_ip}
    User ubuntu
    Port 60022
    # Substitua pelo caminho completo da chave se necessário
    IdentityFile ~/caminho/para/chave-cazia.pem 
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# 2. Configuração para Managers e Workers (Rede Privada)
Host 10.0.*
    User ubuntu
    IdentityFile ~/caminho/para/chave-cazia.pem
    # CRÍTICO: Usa o 'haproxy' como ProxyCommand
    ProxyCommand ssh haproxy -W %h:%p
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
# --- FIM: CONFIGURAÇÃO CAZIA SWARM ---
EOT
}