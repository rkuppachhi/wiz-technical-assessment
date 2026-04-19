provider "aws" {
  region = "us-east-1"
}

# 1. STORAGE (Requirement: "Publicly readable")
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

# 2. OVERLY PERMISSIVE ROLE (Requirement: "able to create VMs")
# Ref: VM should be granted overly permissive CSP permissions
resource "aws_iam_role" "vm_admin" {
  name = "wiz-admin-role-rahul"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "://amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "admin_attach" {
  role       = aws_iam_role.vm_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess" # THE "TOXIC" PART
}

resource "aws_iam_instance_profile" "vm_profile" {
  name = "wiz-vm-profile-rahul"
  role = aws_iam_role.vm_admin.name
}

# 3. SECURITY GROUP (Requirement: "SSH open to public internet")
resource "aws_security_group" "ssh_open" {
  name   = "allow_all_ssh_rahul"
  vpc_id = "vpc-00482dedff0612c97" # Using wizlabs-VPC

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
  ami                    = "ami-053b0d53c279acc90" 
  instance_type          = "t3.micro"
  subnet_id              = "subnet-0c07814355cfccdae" # Public Subnet
  vpc_security_group_ids = [aws_security_group.ssh_open.id]
  
  # NEW: ATTACHING THE PERMISSIVE ROLE
  iam_instance_profile   = aws_iam_instance_profile.vm_profile.name

  tags = { Name = "Wiz-Vulnerable-VM" }
}
