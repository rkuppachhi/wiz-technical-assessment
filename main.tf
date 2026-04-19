provider "aws" {
  region = "us-east-1"
}

# This creates a random suffix so your S3 bucket name never collides again
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# 1. THE NETWORK (Custom VPC to avoid "No Default VPC" error)
resource "aws_vpc" "wiz_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "wiz-final-vpc-${random_string.suffix.result}" }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.wiz_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a" # Fixes the zonal capacity error
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wiz_vpc.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wiz_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# 2. THE LEAKY BUCKET (Requirement: "publicly readable and listable")
resource "aws_s3_bucket" "backups" {
  bucket = "wiz-rahul-backup-${random_string.suffix.result}"
}

resource "aws_s3_bucket_public_access_block" "open" {
  bucket = aws_s3_bucket.backups.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 3. THE SECURITY GROUP (Requirement: "SSH must be exposed to the public internet")
resource "aws_security_group" "ssh_open" {
  name   = "allow_all_ssh_${random_string.suffix.result}"
  vpc_id = aws_vpc.wiz_vpc.id
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

# 4. THE VM (Requirement: "1+ year outdated version of Linux")
resource "aws_instance" "mongo_vm" {
  ami                    = "ami-053b0d53c279acc90" # Ubuntu 22.04
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.ssh_open.id]
  tags = { Name = "Wiz-Vulnerable-VM" }
}
