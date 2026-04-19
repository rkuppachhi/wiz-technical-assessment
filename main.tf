provider "aws" {
  region = "us-east-1"
}

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

# 2. OVERLY PERMISSIVE ROLE (IAM TRAP)
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

# 3. SECURITY GROUP (NETWORK TRAP)
resource "aws_security_group" "ssh_open" {
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

# 4. DATABASE VM
resource "aws_instance" "mongo_vm" {
  ami                    = "ami-053b0d53c279acc90"
  instance_type          = "t3.micro"
  subnet_id              = "subnet-0c07814355cfccdae"
  vpc_security_group_ids = [aws_security_group.ssh_open.id]
  iam_instance_profile   = aws_iam_instance_profile.vm_profile.name
  tags = { Name = "Wiz-Vulnerable-VM-Final" }
}

# 5. EKS CLUSTER (CLOUD NATIVE REQUIREMENT)
resource "aws_eks_cluster" "wiz_cluster" {
  name     = "wiz-tasky-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = ["subnet-0c07814355cfccdae", "subnet-0cc2a9443933c6ff4"]
  }
}

resource "aws_eks_node_group" "tasky_nodes" {
  cluster_name    = aws_eks_cluster.wiz_cluster.name
  node_group_name = "tasky-workers"
  node_role_arn   = aws_iam_role.eks_nodes_role.arn
  subnet_ids      = ["subnet-0c07814355cfccdae", "subnet-0cc2a9443933c6ff4"]

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }
  instance_types = ["t3.medium"]
}

# 6. EKS IAM ROLES (FIXED WITH SUFFIX)
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "eks.amazonaws.com" } }]
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
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
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
