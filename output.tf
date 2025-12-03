## 🚀 OUTPUTS ESSENCIAIS PARA USO E DEBUG

# 1. IP Público do Bastion Host
# Usado para acesso manual via SSH
output "bastion_ip" {
  description = "IP Público do Bastion Host para acesso SSH na porta 60022."
  value       = aws_instance.bastion.public_ip
}

# 2. DNS do Network Load Balancer (NLB)
# Usado para configurar o CNAME no Cloudflare
output "nlb_dns_name" {
  description = "DNS Name do Network Load Balancer (NLB) para Ingress."
  value       = aws_lb.swarm_nlb.dns_name
}

# 3. IPs Privados dos Managers
# Usado para debug e comandos internos do cluster
output "manager_private_ips" {
  description = "Lista de IPs privados dos nós Manager."
  value       = values(aws_instance.manager)[*].private_ip
}

# 4. Comando SSH de Acesso (Exemplo)
# Facilita o acesso rápido ao Bastion
output "ssh_bastion_command" {
  description = "Comando SSH para acesso ao Bastion Host."
  value       = "ssh -i chave-cazia.pem -p 60022 ubuntu@${aws_instance.bastion.public_ip}"
}

output "ssh_manager_01_proxy_command" {
  description = "Comando para SSH no PRIMEIRO MANAGER (Master) via Bastion Host Proxy."
  value = format(
    "ssh -i chave-cazia.pem -o ProxyCommand=\"ssh -W %%h:%%p -i chave-cazia.pem -p 60022 ubuntu@%s\" ubuntu@%s",
    aws_instance.bastion.public_ip, # IP Público do Bastion
    values(aws_instance.manager)[0].private_ip # IP Privado do Manager
  )
}

output "ssh_config_proxy_block" {
  description = "Bloco de configuração SSH para acesso aos nós privados via Bastion."
  value = <<-EOT
# --- INÍCIO: CONFIGURAÇÃO CAZIA SWARM ---
# 1. Configuração do Bastion Host
Host bastion
    HostName ${aws_instance.bastion.public_ip}
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
    # CRÍTICO: Usa o 'bastion' como ProxyCommand
    ProxyCommand ssh bastion -W %h:%p
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
# --- FIM: CONFIGURAÇÃO CAZIA SWARM ---
EOT
}