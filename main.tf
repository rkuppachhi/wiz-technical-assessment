provider "aws" {
  region = "us-east-1"
}

# 1. STORAGE (Requirement: "Publicly readable")
resource "aws_s3_bucket" "backups" {
  bucket = "wiz-rahul-kuppachhi-final-verified-99" # Change if "AlreadyExists"
}

resource "aws_s3_bucket_public_access_block" "open" {
  bucket = aws_s3_bucket.backups.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 2. SECURITY (Requirement: "SSH open to public internet")
resource "aws_security_group" "ssh_open" {
  name   = "allow_all_ssh_rahul"
  vpc_id = "vpc-00482dedff0612c97" 

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. THE VM (Requirement: "1+ year outdated version of Linux")
resource "aws_instance" "mongo_vm" {
  ami                    = "ami-053b0d53c279acc90" 
  instance_type          = "t3.micro"
  subnet_id              = "subnet-0c07814355cfccdae" 
  vpc_security_group_ids = [aws_security_group.ssh_open.id]
  tags                   = { Name = "Wiz-Vulnerable-VM" }
}
