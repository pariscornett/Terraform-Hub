#Bootstrapping a Remote Backend in a Green Field 

#FIRST APPLY--Declare Provider w/ no specified backend (bc no bucket yet exists to hold the state files). This defaults to local backend
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

#SECOND APPLY--Once the S3 bucket and DynamoDB table have been provisioned, we can define the backend in the above terraform block. 
##Re-run terraform init and answer "yes" to prompt re: configuring the backend
/* terraform {
  backend "s3" {
    bucket = "pariscornett-terraform-hub-state" 
    key = "tf_infra/terraform.tfstate"          #"key" refers to the path you want the backup to map to in the s3 bucket
    region = "us-east-1"
    dynamodb_table = "pariscornett-terraform-hub-state-locking"
    encrypt = true
  }
} */


#Basic configuration of the AWS provider
provider "aws" {
  region = "us-east-1"
}

#Create S3 bucket to store state file
resource "aws_s3_bucket" "tf_state" {
  bucket = "pariscornett-terraform-hub-state"      #forces new bucket. make sure name is unique or tf will throw error
  force_destroy = true        #all objects (even locked objects) are destroyed when the bucket is destroyed to avoid error
}

#Enable versioning on the bucket 
resource "aws_s3_bucket_versioning" "tf_state_versioning" {
  bucket = "pariscornett-terraform-hub-state"
  versioning_configuration {
    status = "Enabled"
  }
}

#Enable simple server-side encryption on the bucket (you could use KMS keys here, but for simplicity, I've left it out.)
resource "aws_s3_bucket_server_side_encryption_configuration" "encrypt_tf_state" {
  bucket = "pariscornett-terraform-hub-state"
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


#Create DynamoDB table to lock tf file in S3 bucket
resource "aws_dynamodb_table" "tf_lock" {
  name = "pariscornett-terraform-hub-state-locking"
  billing_mode = "PAY_PER_REQUEST"    #defaults to PROVISIONED if not specified
  hash_key = "LockID"                 #critical attribute for this to actually work
  attribute {
    name = "LockID"                   #sets attribute name
    type = "S"                        #refers to data type. "S" = string, "N" = number, "B" = binary
  }
}