locals {
  region          = "us-east-1"
  name            = "${terraform.workspace}-cluster"
  vpc_cidr        = "10.123.0.0/16"
  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.123.1.0/24", "10.123.2.0/24"]
  private_subnets = ["10.123.3.0/24", "10.123.4.0/24"]
  intra_subnets   = ["10.123.5.0/24", "10.123.6.0/24"]
  tags = {
    Example = local.name
  }
}

provider "aws" {
  region = local.region
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
  intra_subnets   = local.intra_subnets

  enable_nat_gateway        = true
  map_public_ip_on_launch   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

resource "aws_instance" "k8s_nodes" {
  count         = 2
  ami           = "ami-0c02fb55956c7d316" # Amazon Linux 2 AMI (update if needed)
  instance_type = "t3.medium"
  key_name      = "devops-key" # Make sure this key pair exists in your AWS

  subnet_id              = element(module.vpc.public_subnets, count.index)
  associate_public_ip_address = true
  vpc_security_group_ids = [module.vpc.default_security_group_id]

  tags = {
    Name = "${local.name}-node-${count.index}"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y docker
              systemctl start docker
              systemctl enable docker

              # Install kubelet, kubeadm, kubectl
              cat <<EOT > /etc/yum.repos.d/kubernetes.repo
              [kubernetes]
              name=Kubernetes
              baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
              enabled=1
              gpgcheck=1
              repo_gpgcheck=1
              gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
              EOT

              yum install -y kubelet kubeadm kubectl
              systemctl enable --now kubelet
              EOF
}

output "instance_ips" {
  value = aws_instance.k8s_nodes[*].public_ip
}
