provider "aws" {
  region = "us-east-1"
}

# 1. CREATE THE NETWORK (Required because Lab has no Default VPC)
resource "aws_vpc" "wiz_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "wiz-sovereign-vpc" }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.wiz_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a" # THIS LINE FIXES THE ERROR
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

# 2. THE LEAKY BUCKET (Stays the same)
resource "aws_s3_bucket" "backups" {
  bucket = "wiz-rahul-kuppachhi-unique-998877" # CHANGE THIS NAME
}

resource "aws_s3_bucket_public_access_block" "open" {
  bucket = aws_s3_bucket.backups.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 3. THE SECURITY GROUP (Fixed to use the new VPC)
resource "aws_security_group" "ssh_open" {
  name   = "allow_all_ssh"
  vpc_id = aws_vpc.wiz_vpc.id # THIS LINE FIXES YOUR ERROR

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

# 4. THE VM (Fixed to use the new Subnet)
resource "aws_instance" "mongo_vm" {
  ami                    = "ami-053b0d53c279acc90" 
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id # THIS LINE FIXES YOUR ERROR
  vpc_security_group_ids = [aws_security_group.ssh_open.id]
}