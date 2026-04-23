provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

# 1. STORAGE
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

# S3 Bucket Policy: Public read + listing (requirement)
resource "aws_s3_bucket_policy" "public_read" {
  bucket     = aws_s3_bucket.backups.id
  depends_on = [aws_s3_bucket_public_access_block.open]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:ListBucket"]
        Resource  = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*"
        ]
      },
      {
        Sid       = "AWSConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.backups.arn
      },
      {
        Sid       = "AWSConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.backups.arn}/AWSLogs/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

# ECR Repository for Tasky container image
resource "aws_ecr_repository" "tasky" {
  name                 = "wiz-tasky-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# 2. OVERLY PERMISSIVE ROLE (VM Admin)
resource "aws_iam_role" "vm_admin" {
  name = "wiz-admin-role-rahul-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
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

# 3. NETWORK (Using existing NAT Gateway — no new EIP needed)
data "aws_vpc" "wiz" { id = "vpc-00482dedff0612c97" }

resource "aws_subnet" "private_1b" {
  vpc_id            = data.aws_vpc.wiz.id
  cidr_block        = "10.50.4.0/24"
  availability_zone = "us-east-1b"
  tags = { 
    Name = "wiz-private-1b"
    "kubernetes.io/role/internal-elb" = "1" 
  }
}

resource "aws_subnet" "private_1c" {
  vpc_id            = data.aws_vpc.wiz.id
  cidr_block        = "10.50.5.0/24"
  availability_zone = "us-east-1c"
  tags = { 
    Name = "wiz-private-1c"
    "kubernetes.io/role/internal-elb" = "1" 
  }
}

resource "aws_route_table" "private" {
  vpc_id = data.aws_vpc.wiz.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = "nat-0cdeec23a76d14158"
  }
}

resource "aws_route_table_association" "p1" {
  subnet_id      = aws_subnet.private_1b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "p2" {
  subnet_id      = aws_subnet.private_1c.id
  route_table_id = aws_route_table.private.id
}

# 4. DATABASE VM
resource "aws_security_group" "ssh_open" {
  name   = "allow_ssh_rahul_${random_string.suffix.result}"
  vpc_id = data.aws_vpc.wiz.id
  ingress { 
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
  ingress { 
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.wiz.cidr_block] 
  }
  egress { 
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] 
  }
}

resource "aws_instance" "mongo_vm" {
  ami                    = "ami-053b0d53c279acc90"
  instance_type          = "t3.micro"
  subnet_id              = "subnet-0c07814355cfccdae"
  private_ip             = "10.50.0.100"
  vpc_security_group_ids = [aws_security_group.ssh_open.id]
  iam_instance_profile   = aws_iam_instance_profile.vm_profile.name
  tags = { Name = "Wiz-Vulnerable-VM-Final" }

  user_data = <<-USERDATA
#!/bin/bash
set -e

# Install MongoDB 5.0 (1+ year outdated — current is 7.x)
wget -qO - https://www.mongodb.org/static/pgp/server-5.0.asc | apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/5.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-5.0.list
apt-get update
apt-get install -y mongodb-org

# Configure MongoDB to listen on all interfaces
sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf

# Start MongoDB (no auth first to create user)
systemctl start mongod
systemctl enable mongod
sleep 5

# Create admin user
mongo admin --eval 'db.createUser({user: "admin", pwd: "wizpassword123", roles: [{role: "root", db: "admin"}]})'

# Enable authentication
sed -i '/^#security:/a\\security:\n  authorization: enabled' /etc/mongod.conf
systemctl restart mongod

# Install AWS CLI for backups
apt-get install -y awscli

# Daily backup cron job — dumps MongoDB to S3 bucket
echo "0 2 * * * mongodump --uri='mongodb://admin:wizpassword123@localhost:27017' --authenticationDatabase=admin --out=/tmp/mongo-backup && aws s3 sync /tmp/mongo-backup s3://wiz-rahul-kuppachhi-final-verified-99/backups/\$(date +\%%Y-\%%m-\%%d)/ && rm -rf /tmp/mongo-backup" | crontab -
USERDATA
}

# 5. EKS
resource "aws_eks_cluster" "wiz_cluster" {
  name     = "wiz-tasky-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  vpc_config { 
    subnet_ids = [aws_subnet.private_1b.id, aws_subnet.private_1c.id] 
  }
  enabled_cluster_log_types = ["audit", "api", "authenticator"]
}

resource "aws_eks_node_group" "tasky_nodes" {
  cluster_name    = aws_eks_cluster.wiz_cluster.name
  node_group_name = "tasky-workers"
  node_role_arn   = aws_iam_role.eks_nodes_role.arn
  subnet_ids      = [aws_subnet.private_1b.id, aws_subnet.private_1c.id]
  scaling_config { 
    desired_size = 1
    max_size     = 1
    min_size     = 1 
  }
  instance_types = ["t3.medium"]
}

# 6. EKS ROLES
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ 
      Action = "sts:AssumeRole", 
      Effect = "Allow", 
      Principal = { Service = "eks.amazonaws.com" } 
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role" "eks_nodes_role" {
  name = "eks-node-role-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ 
      Action = "sts:AssumeRole", 
      Effect = "Allow", 
      Principal = { Service = "ec2.amazonaws.com" } 
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes_role.name
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes_role.name
}

resource "aws_iam_role_policy_attachment" "ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes_role.name
}

# ========== CLOUD NATIVE SECURITY CONTROLS ==========

# ---------- DETECTIVE CONTROL: GuardDuty ----------
resource "aws_guardduty_detector" "main" {
  enable = true
}

# ---------- DETECTIVE CONTROL: Security Hub ----------
resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "aws_best_practices" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:us-east-1::standards/aws-foundational-security-best-practices/v/1.0.0"
  timeouts {
    create = "10m"
  }
}

# ---------- PREVENTATIVE CONTROL: AWS Config ----------
resource "aws_iam_role" "config_role" {
  name = "wiz-config-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "main" {
  name     = "wiz-config-recorder"
  role_arn = aws_iam_role.config_role.arn
}

resource "aws_config_delivery_channel" "main" {
  name           = "wiz-config-channel"
  s3_bucket_name = aws_s3_bucket.backups.id
  depends_on     = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

resource "aws_config_config_rule" "s3_public_read" {
  name = "s3-bucket-public-read-prohibited"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
  depends_on = [aws_config_configuration_recorder.main]
}
