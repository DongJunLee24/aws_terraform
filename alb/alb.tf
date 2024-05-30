provider "aws" {
  region = "ap-northeast-1"
}

# ALB용 보안 그룹 생성
resource "aws_security_group" "alb_sg" {
  name = "alb_sg"
  description = "Allow inbound traffic"
  vpc_id = data.aws_vpc.selected.id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
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

data "aws_subnet" "public_subnet_a" {
  filter {
    name   = "tag:Name"
    values = ["public-subnet-a"]
  }
}

data "aws_eks_cluster" "cluster" {
  name = "my-cluster"
}

data "aws_eks_cluster_auth" "cluster" {
  name = data.aws_eks_cluster.cluster.name
}

resource "aws_iam_policy" "alb_ingress" {
  name        = "ALBIngressControllerIAMPolicy"
  path        = "/"
  description = "IAM policy for ALB Ingress Controller"
  policy      = file("/root/alb/iam_policy.json")
}

# ALB 생성
resource "aws_lb" "main" {
  name = "my-alb" # ALB 이름 설정
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb_sg.id]
  subnets = [data.aws_subnet.public_subnet_a.id, data.aws_subnet.public_subnet_c.id]

  enable_deletion_protection = false # 삭제 보호 활성화 여부
}

resource "aws_lb_target_group" "main" {
  name     = "example-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.selected.id
  health_check {
    path                = "/*"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200-299"
  }
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

data "aws_instances" "web" {
  instance_tags = {
    Name = "web"
  }
}

resource "aws_lb_target_group_attachment" "web" {
  for_each         = toset(data.aws_instances.web.ids)
  
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = each.value # 여기서는 각 인스턴스 ID를 이용합니다.
  port             = 30001
}

resource "aws_route53_zone" "example" {
  name = "adaptercloud.store"
}

resource "aws_route53_record" "example" {
  zone_id = aws_route53_zone.example.zone_id
  name    = "adaptercloud.store"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}