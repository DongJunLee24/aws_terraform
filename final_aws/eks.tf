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

data "aws_subnet" "private_subnet_a" {
  filter {
    name   = "tag:Name"
    values = ["private-subnet-a"]
  }
}

data "aws_subnet" "private_subnet_c" {
  filter {
    name   = "tag:Name"
    values = ["private-subnet-c"]
  }
}

# 보안 그룹을 데이터 소스로 불러오기
data "aws_security_group" "eks_node_security_group" {
  filter {
    name   = "tag:Name"
    values = ["eks-node-security-group"]
  }
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "20.11.1"
  cluster_name    = "my-cluster"
  cluster_version = "1.29"
  vpc_id          = data.aws_vpc.selected.id
  subnet_ids      = [data.aws_subnet.private_subnet_a.id, data.aws_subnet.private_subnet_c.id]
  tags            = {
    Name = "my-cluster"
  }

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
  coredns = {
    most_recent = true
  }
  kube-proxy = {
    most_recent = true
  }
}

  create_iam_role = false
  iam_role_arn = "arn:aws:iam::471112818163:role/FINAL-EKS-CLUSTER-ROLE"
  create_cluster_security_group = false
  cluster_security_group_id   = data.aws_security_group.eks_node_security_group.id

  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    instance_types = ["t3.medium"]
  }

  eks_managed_node_groups = {
    web_group = {
      name = "web"
      min_size     = 2
      max_size     = 3
      desired_size = 2

      instance_type = "t3.medium"
      key_name = "FINAL-KEY-PAIR"
      cluster_primary_security_group_id = data.aws_security_group.eks_node_security_group.id
      vpc_security_group_ids = [data.aws_security_group.eks_node_security_group.id]
      subnet_ids = [data.aws_subnet.private_subnet_a.id, data.aws_subnet.private_subnet_c.id]
      create_iam_role = false
      iam_role_arn = "arn:aws:iam::471112818163:role/FINAL-EKS-NODEGROUP-SG"

      tags = {
        Name = "web"
      }
    }

    was_group = {
      name = "was"
      min_size     = 2
      max_size     = 3
      desired_size = 2

      instance_type = "t3.medium"
      key_name = "FINAL-KEY-PAIR"
      cluster_primary_security_group_id = data.aws_security_group.eks_node_security_group.id
      vpc_security_group_ids = [data.aws_security_group.eks_node_security_group.id]
      subnet_ids = [data.aws_subnet.private_subnet_a.id, data.aws_subnet.private_subnet_c.id]
      create_iam_role = false
      iam_role_arn = "arn:aws:iam::471112818163:role/FINAL-EKS-NODEGROUP-SG"

      tags = {
        Name = "was"
      }
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# 데이터 소스 추가
data "aws_caller_identity" "current" {}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# aws-auth ConfigMap 설정
resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = jsonencode([
      {
        rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/FINAL-EKS-NODEGROUP-SG"
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = [
          "system:bootstrappers",
          "system:nodes"
        ]
      }
    ])

    mapUsers = jsonencode([
      {
        userarn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/FINAL-LDJ"
        username = "FINAL-LDJ"
        groups   = [
          "system:masters"
        ]
      }
    ])
  }
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

# provider "helm" {
#   kubernetes {
#     config_path = "~/.kube/config"
#   }
# }

# resource "helm_release" "alb_ingress_controller" {
#   name       = "alb-load-balancer-controller"
#   repository = "https://aws.github.io/eks-charts"
#   chart      = "aws-load-balancer-controller"
#   namespace  = "kube-system"

#   set {
#     name  = "clusterName"
#     value = "my-cluster"
#   }

#   set {
#     name  = "region"
#     value = "ap-northeast-1"
#   }

#   set {
#     name  = "vpcId"
#     value = data.aws_vpc.selected.id
#   }
# }