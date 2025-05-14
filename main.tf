#Declare Provider(s)
terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.0"
        }
    }
}

#Configure Provider
provider "aws" {
  region = "us-east-1"
}

#Create an EC2 instance
resource "aws_instance" "terraform_test_instance" {
  ami = "ami-0f88e80871fd81e91"  #amazon linux 2023 ami, free tier
  instance_type = "t2.micro"
}
