provider "aws" {
  region = "us-east-1"
}

# The Leaky S3 Bucket (Public)
resource "aws_s3_bucket" "backups" {
  bucket = "wiz-rahul-backups-2026" # Must be unique
}

resource "aws_s3_bucket_public_access_block" "open" {
  bucket = aws_s3_bucket.backups.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# The Vulnerable VM (SSH Open to World)
resource "aws_security_group" "ssh_open" {
  name = "allow_all_ssh"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "mongo_vm" {
  ami           = "ami-053b0d53c279acc90" # Ubuntu 22.04
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.ssh_open.id]
}
