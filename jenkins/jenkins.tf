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

# 서브넷을 이름으로 검색하여 서브넷 ID를 가져오는 데이터 소스
data "aws_subnet" "public_subnet_a" {
  filter {
    name   = "tag:Name"
    values = ["public-subnet-a"]
  }

  vpc_id = data.aws_vpc.selected.id
}

# Jenkins용 보안 그룹 생성
resource "aws_security_group" "jenkins_sg" {
  name   = "jenkins-sg"
  vpc_id = data.aws_vpc.selected.id

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jenkins-sg"
  }
}

resource "aws_instance" "jenkins_instance" {
  ami                    = "ami-0689666598efc9552"  # Jenkins를 실행할 AMI ID로 변경해야 합니다.
  instance_type          = "t3.large"
  subnet_id              = data.aws_subnet.public_subnet_a.id
  key_name               = "FINAL-KEY-PAIR"  # 사용하고 있는 SSH 키 페어의 이름으로 대체해야 합니다.
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  associate_public_ip_address = true

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo wget -O /etc/yum.repos.d/jenkins.repo http://pkg.jenkins.io/redhat-stable/jenkins.repo",
      "sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key",
      "sudo yum upgrade",
      "sudo dnf install java-17-amazon-corretto -y",
      "sudo yum install jenkins -y",
      "sudo systemctl start jenkins",
      "sudo systemctl enable jenkins",
      "sudo yum install docker -y",
      "sudo service docker start",
      "sudo usermod -a -G docker ec2-user",
      "sudo usermod -a -G docker jenkins"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("/root/jenkins/FINAL-KEY-PAIR.pem")
      host        = aws_instance.jenkins_instance.public_ip
    }
  }

  tags = {
    Name = "jenkins-instance"
  }
}
