provider "aws" {
  region = "us-east-1"
}

# 1. RANDOM SUFFIX (Prevents "Duplicate Name" errors)
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

# 2. STORAGE (Requirement: "Publicly readable")
resource "aws_s3_bucket" "backups" {
  bucket = "wiz-rahul-kuppachhi-final-verified-99" 
}

resource "aws_s3_bucket_public_access_block" "open" {
  bucket = aws_s3_bucket.backups.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 3. OVERLY PERMISSIVE ROLE (Requirement: "able to create VMs")
resource "aws_iam_role" "vm_admin" {
  name = "wiz-admin-role-rahul-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com" # FIXED SYNTAX
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "admin_attach" {
  role       = aws_iam_role.vm_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "vm_profile" {
  name = "wiz-vm-profile-rahul-${random_string.suffix.result}"
  role = aws_iam_role.vm_admin.name
}

# 4. SECURITY GROUP (Requirement: "SSH open to public internet")
resource "aws_security_group" "ssh_open" {
  # Added suffix to name to prevent "InvalidGroup.Duplicate" error
  name   = "allow_ssh_rahul_${random_string.suffix.result}"
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

# 5. THE VM (Requirement: "1+ year outdated version of Linux")
resource "aws_instance" "mongo_vm" {
  ami                    = "ami-053b0d53c279acc90" 
  instance_type          = "t3.micro"
  subnet_id              = "subnet-0c07814355cfccdae"
  vpc_security_group_ids = [aws_security_group.ssh_open.id]
  iam_instance_profile   = aws_iam_instance_profile.vm_profile.name

  tags = { 
    Name = "Wiz-Vulnerable-VM-Final" 
  }
}
