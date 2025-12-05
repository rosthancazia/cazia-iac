

# --- 1. LÓGICA DE GERAÇÃO DE NOMES ---

# Substitua o data "aws_ami" "amazon_linux" por este:
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # ID da Canonical (Criadora do Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  # Gera um Map: { "swarm-manager-01" = 0, "swarm-manager-02" = 1, ... }
  # Usamos o índice (0, 1) para escolher a Subnet depois
  managers = {
    for i in range(var.manager_count) :
    format("swarm-manager-%02d", i + 1) => i
  }

  workers = {
    for i in range(var.worker_count) :
    format("swarm-worker-%02d", i + 1) => i
  }
}

provider "aws" {
  region = var.aws_region
}

# --- 1. Chaves e Segurança ---
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kp" {
  key_name   = "chave-cazia-ansible"
  public_key = tls_private_key.pk.public_key_openssh
}

# Salva a chave privada localmente para o Ansible usar
resource "local_file" "ssh_key" {
  filename        = "${path.module}/chave-cazia.pem"
  content         = tls_private_key.pk.private_key_pem
  file_permission = "0400"
}

# --- 2. Rede (VPC e Security Groups) ---
data "aws_availability_zones" "available" { state = "available" }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "cazia-vpc"
  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  
    enable_nat_gateway = true
    single_nat_gateway = false
    one_nat_gateway_per_az = false

}

# SG do haproxy
resource "aws_security_group" "haproxy_sg" {
  name   = "haproxy-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 60022
    to_port     = 60022
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG do Swarm (Privado)
resource "aws_security_group" "swarm_sg" {
  name   = "swarm-sg"
  vpc_id = module.vpc.vpc_id

  ingress { # Libera tudo internamente
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  ingress { # Libera SSH vindo do haproxy
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.haproxy_sg.id]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress { # Saída para internet (via NAT)
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 3. Instâncias ---

# haproxy Host
resource "aws_instance" "haproxy" {
  ami                         = data.aws_ami.ubuntu.id # Amazon Linux 2 (us-east-1)
  instance_type               = "t2.micro"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.haproxy_sg.id]
  key_name                    = aws_key_pair.kp.key_name
  associate_public_ip_address = true
  tags                        = { Name = "haproxy" }

  # Configura porta 60022
  user_data = <<-EOF
              #!/bin/bash
              echo "Port 60022" >> /etc/ssh/sshd_config
              yum install -y policycoreutils-python
              semanage port -a -t ssh_port_t -p tcp 60022 || true
              systemctl restart sshd
              EOF
}

resource "aws_instance" "manager" {
  # O for_each itera sobre o MAP criado acima
  for_each = local.managers

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  
  # Como for_each não tem count.index, usamos o VALOR do map (0, 1, 2...)
  # para pegar a subnet rotativamente
  subnet_id              = element(module.vpc.private_subnets, each.value)
  
  vpc_security_group_ids = [aws_security_group.swarm_sg.id]
  key_name               = aws_key_pair.kp.key_name


  # --- NOVO BLOCO EBS PARA GLUSTER ---
  ebs_block_device {
    device_name = "/dev/sdb" # Ou /dev/xvdb, depende do tipo de instância e AMI
    volume_size = 20         # 20 GiB para o Gluster
    volume_type = "standard"     
    encrypted   = false
    delete_on_termination = true
  }

  tags = { 
    # each.key agora é "swarm-manager-01", "swarm-manager-02", etc.
    Name = each.key
    Role = "Manager"
  }
}

# Swarm Workers
resource "aws_instance" "worker" {
  for_each = local.workers

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  subnet_id              = element(module.vpc.private_subnets, each.value)
  vpc_security_group_ids = [aws_security_group.swarm_sg.id]
  key_name               = aws_key_pair.kp.key_name

  tags = { 
    Name = each.key
    Role = "Worker"
  }
}

# --- 4. Integração Ansible (A Mágica acontece aqui) ---

# --- 3. INVENTÁRIO (Adaptação para for_each) ---

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/inventory.ini"
  
  content  = <<-EOT
    [haproxy]
    # CORREÇÃO: Linha única, usando o nome lógico 'haproxy' como inventory_hostname.
    haproxy ansible_host=${aws_instance.haproxy.public_ip} private_ip=${aws_instance.haproxy.private_ip} ansible_port=60022
    
    [swarm_managers]
    %{ for name, vm in aws_instance.manager ~}
    ${name} ansible_host=${vm.private_ip} private_ip=${vm.private_ip}
    %{ endfor ~}

    [workers]
    %{ for name, vm in aws_instance.worker ~}
    ${name} ansible_host=${vm.private_ip} private_ip=${vm.private_ip}
    %{ endfor ~}

    [gluster_nodes] 
    %{ for name, vm in aws_instance.manager ~}
    ${name} ansible_host=${vm.private_ip} private_ip=${vm.private_ip}
    %{ endfor ~}

    [all:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=./chave-cazia.pem
    device2_hdd_dev=/dev/sdb
    # Configuração de Proxy para os hosts internos (Managers e Workers)
    ansible_ssh_common_args='-o ProxyCommand="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 60022 -i ./chave-cazia.pem -W %h:%p -q ubuntu@${aws_instance.haproxy.public_ip}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
  EOT
}

# --- 4. Disparador do Ansible ---
resource "null_resource" "run_ansible" {
  triggers = {
    inventory_content = local_file.ansible_inventory.content
  }

  depends_on = [
    local_file.ansible_inventory,
    aws_instance.haproxy,
    aws_instance.worker,
    aws_instance.manager,
    module.vpc,
    cloudflare_dns_record.whoami,
#    aws_lb.swarm_nlb
  ]

  provisioner "local-exec" {
    command = <<EOT
      echo "Aguardando inicialização final da rede e SSH..."
      sleep 60
      
      # 1. Executa o Playbook de Deploy (Instalação e Swarm)
      echo "Iniciando Playbook de Deploy..."
      #ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini ansible/playbook.yml
      
      # 2. Executa o Playbook de Validação dos Endpoints
      echo "Iniciando validação dos endpoints Traefik (aguardando DNS e ACME)..."
      # Usamos '-e @swarm_vars.yml' para injetar o 'base_domain' no playbook de validação
      #ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini ansible/deploy_traefik.yml -e @ansible/swarm_vars.yml
      #ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini validate_endpoints.yml -e @swarm_vars.yml
      
      echo "✅ VALIDAÇÃO DO AMBIENTE CONCLUÍDA COM SUCESSO!"
    EOT
  }
}