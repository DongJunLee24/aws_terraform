provider "aws" {
  region = "ap-northeast-1"
}

# VPC를 이름으로 검색하여 VPC ID를 가져오는 데이터 소스
data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = ["Kcs-VPC"]
  }
}

data "aws_subnet" "public_subnet_c" {
  filter {
    name   = "tag:Name"
    values = ["public-subnet-c"]
  }
}

# 보안 그룹을 이름으로 검색하여 보안 그룹 ID를 가져오는 데이터 소스
data "aws_security_group" "bastion_sg" {
  filter {
    name   = "tag:Name"
    values = ["bastion-sg"]
  }

  vpc_id = data.aws_vpc.selected.id
}

# 외부 스크립트를 실행하여 VPC ID를 가져오는 데이터 소스
data "external" "vpc_id" {
  program = ["bash", "/root/bt_host/get_vpc_id.sh"]
}

# VPC ID를 출력하여 확인
output "vpc_id" {
  value = data.external.vpc_id.result.vpc_id
}

# Bastion Host EC2 인스턴스
resource "aws_instance" "bastion_host" {
  ami                    = "ami-029fb6096b4efb748"  # 예시: Amazon Linux 2 AMI (해당 지역에 맞는 AMI ID로 변경 필요)
  instance_type          = "t3.large"
  subnet_id              = data.aws_subnet.public_subnet_c.id
  key_name               = "FINAL-KEY-PAIR"  # 사용하고 있는 SSH 키 페어의 이름으로 대체해야 합니다.
  vpc_security_group_ids = [data.aws_security_group.bastion_sg.id]
  associate_public_ip_address = true

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y git",
      "sudo yum install epel-release",
      "sudo yum install jq",
      "echo \"alias k='kubectl'\" >> ~/.bashrc",
      "source ~/.bashrc",
      "curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\"",
      "unzip awscliv2.zip",
      "sudo ./aws/install",
      "aws configure set aws_access_key_id ${var.aws_access_key_id}",
      "aws configure set aws_secret_access_key ${var.aws_secret_access_key}",
      "aws configure set default.region ap-northeast-1",
      "curl -LO https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl",
      "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl",
      "curl --silent --location \"https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz\" | tar xz -C /tmp",
      "sudo mv /tmp/eksctl /usr/local/bin",
      "aws eks update-kubeconfig --region ap-northeast-1 --name my-cluster",
      "git clone https://github.com/DongJunLee24/aws_alb.git",
      "cd aws_alb",
      "kubectl delete -f service.yaml",
      "kubectl apply -f service.yaml",
      "kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json",
      "curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3",
      "chmod 700 get_helm.sh",
      "./get_helm.sh",
      "helm repo add eks https://aws.github.io/eks-charts",
      "helm repo update",
      "helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=my-cluster --set serviceAccount.create=true --set region=ap-northeast-1 --set vpcId=${data.external.vpc_id.result.vpc_id} --set serviceAccount.name=aws-load-balancer-controller",
      "kubectl apply -f ingress.yaml"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("/root/bt_host/FINAL-KEY-PAIR.pem")
      host        = aws_instance.bastion_host.public_ip
    }
  }

  tags = {
    Name = "bastion-host"
  }
}