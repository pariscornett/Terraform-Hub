# IMPORTANT: this assumes that a remote backend has been configured. See prepare_remote_backend/main.tf 
terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "tf-hub-state20250521140920927600000001"  # hard coding for now, but looking for the best way to reference this 
    key = "tf_infra/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "tf-hub-state-locking"            # hard coding for now, but looking for the best way to reference this
    encrypt = true
  }
}

provider "aws" {
  region = "us-east-1"
}

#Create 2 EC2 instances
resource "aws_instance" "web_server_1" {
  ami = "ami-0953476d60561c955"          #64-bit Amazon Linux 2023 | Free Tier
  instance_type = "t2.micro"             #1vCPU | 1 GiB | Free Tier
  security_groups = [aws_security_group.web_apps.name]
  user_data       = <<-END
              #!/bin/bash
              echo "Web Application 1" > index.html
              python3 -m http.server 8080 &
              END

  tags = {
    name = "Tag Name"
    application = "Application Name"
    environment = "Environment Name"
  }
}

resource "aws_instance" "web_server_2" {
  ami = "ami-0953476d60561c955"          #64-bit Amazon Linux 2023 | Free Tier
  instance_type = "t2.micro"             #1vCPU | 1 GiB | Free Tier
  security_groups = [aws_security_group.web_apps.name]
  user_data       = <<-END
              #!/bin/bash
              echo "Web Application 1" > index.html
              python3 -m http.server 8080 &
              END

  tags = {
    name = "Tag Name"
    application = "Application Name"
    environment = "Environment Name"
  }         
}

#Create 1 S3 bucket with server side encryption and versioning
resource "aws_s3_bucket" "source_code" {
  bucket_prefix = "app-source-code"       #bucket_prefix will make sure the bucket name is unique and avoid erroring out 
  force_destroy = true                          #ensures all objects will be deleted when bucket is destroyed. includes locked objects

  tags = {
    name = "Tag Name"
    application = "Application Name"
    environment = "Environment Name"
  }
}

resource "aws_s3_bucket_versioning" "source_code_versioning" {
  bucket = aws_s3_bucket.source_code.bucket
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source_code_encryption" {
  bucket = aws_s3_bucket.source_code.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#Reference default AWS VPC and Subnet with data block
data "aws_vpc" "default_vpc" {
  default = true
}

data "aws_subnets" "default_subnets" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default_vpc.id]
  }
}
#Create 1 Security Group for open ingress on HTTP
#Create 1 Security Group for ALB with 80 ingress and open egress
#REMINDER: AWS Security Groups are stateful
resource "aws_security_group" "web_apps" {
  name = "web-apps-security-group"
  description = "web apps security group"
  vpc_id = data.aws_vpc.default_vpc.id              #this defaults to the default vpc's id, so not necessary, but including for templating purposes
  
  tags = {
    name = "Tag Name"
    application = "Application Name"
    environment = "Environment Name"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_web" {
  security_group_id = aws_security_group.web_apps.id

  ip_protocol = "tcp"
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 8080
  to_port = 8080
}

resource "aws_security_group" "alb" {
  name = "alb_security_group"
  description = "alb security group"
  vpc_id = data.aws_vpc.default_vpc.id              #this defaults to the default vpc's id, so not necessary, but including for templating purposes
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_alb" {
  security_group_id = aws_security_group.alb.id

  ip_protocol = "tcp"
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 8080
  to_port = 8080
}

resource "aws_vpc_security_group_egress_rule" "allow_all" {
  security_group_id = aws_security_group.alb.id

  ip_protocol = "-1"
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 0
  to_port = 0
}

#Create an ALB & configure it to listen on HTTP. Define 2 ec2 instances from above as target groups, and configure ALB rules
resource "aws_lb" "alb" {
  name = "web-apps-load-balancer"
  load_balancer_type = "application"
  subnets = data.aws_subnets.default_subnets.ids
  security_groups = [aws_security_group.alb.id]

  tags = {
    name = "Tag Name"
    application = "Application Name"
    environment = "Environment Name"
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port = 8080
  protocol = "HTTP"
   
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404 Page not Found"
      status_code = 404
    }
  }
}

resource "aws_lb_target_group" "web_apps" {
  name = "web-apps-tg"
  port = 8080
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "web_server_1" {
  target_group_arn = aws_lb_target_group.web_apps.arn
  target_id        = aws_instance.web_server_1.id
  port = 8080
}

resource "aws_lb_target_group_attachment" "web_server_2" {
  target_group_arn = aws_lb_target_group.web_apps.arn
  target_id = aws_instance.web_server_2.id
  port = 8080
}

resource "aws_lb_listener_rule" "web_apps" {
  listener_arn = aws_alb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_apps.arn
  }
}
#Make a security group for the ALB and configure inbound/outbound rules


#Configure Route53
resource "aws_route53_zone" "primary" {
  name = "pariscornett.com"
}

resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

#Create Postgres database instance
resource "aws_db_instance" "db" {
  allocated_storage = 20
  # This allows any minor version within the major engine_version
  # defined below, but will also result in allowing AWS to auto
  # upgrade the minor version of your DB. This may be too risky
  # in a real production environment.
  auto_minor_version_upgrade = true
  storage_type               = "standard"
  engine                     = "postgres"
  engine_version             = "12"
  instance_class             = "db.t3.micro"
  db_name                    = "webAppBackend"
  username                   = "foo"
  password                   = "foobarbaz"
  skip_final_snapshot        = true
}