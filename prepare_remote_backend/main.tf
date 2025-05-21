#Bootstrapping a Remote Backend in a Green Field 

#IMPORTANT--Declare Provider w/ no specified backend (bc no bucket yet exists to hold the state files). This defaults to local backend. THIS IS THE ONLY TIME the Terraform block will not include the details of the backend that we will create with this script. See webApp/main.tf's terraform block for an example of how to utilize the S3 bucket w/ table locking we create here as the backend.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}


#Basic configuration of the AWS provider
provider "aws" {
  region = "us-east-1"
}

#Create S3 bucket to store state file
resource "aws_s3_bucket" "tf_state" {
  bucket_prefix = "tf-hub-state"    #bucket_prefix will make sure the bucket name is unique and avoid erroring out. preferable to the simpler bucket argument which will error if the chosen name isn't unique. 
  force_destroy = true        #all objects (even locked objects) are destroyed when the bucket is destroyed to avoid error
}

#Enable versioning on the bucket 
resource "aws_s3_bucket_versioning" "tf_state_versioning" {
  bucket = aws_s3_bucket.tf_state.bucket
  versioning_configuration {
    status = "Enabled"
  }
}

#Enable simple server-side encryption on the bucket (you could use KMS keys here, but for simplicity, I've left it out.)
resource "aws_s3_bucket_server_side_encryption_configuration" "encrypt_tf_state" {
  bucket = aws_s3_bucket.tf_state.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


#Create DynamoDB table to lock tf file in S3 bucket
resource "aws_dynamodb_table" "tf_lock" {
  name = "tf-hub-state-locking"
  billing_mode = "PAY_PER_REQUEST"    #defaults to PROVISIONED if not specified
  hash_key = "LockID"                 #critical attribute for this to actually work
  attribute {
    name = "LockID"                   #sets attribute name
    type = "S"                        #refers to data type. "S" = string, "N" = number, "B" = binary
  }
}