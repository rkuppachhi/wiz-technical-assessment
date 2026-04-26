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

# Tag existing public subnets for ALB discovery (need 2 in different AZs)
resource "aws_ec2_tag" "public_1a_elb" {
  resource_id = "subnet-0c07814355cfccdae"
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "public_1a_cluster" {
  resource_id = "subnet-0c07814355cfccdae"
  key         = "kubernetes.io/cluster/wiz-tasky-cluster"
  value       = "shared"
}

resource "aws_ec2_tag" "public_1c_elb" {
  resource_id = "subnet-0cc2a9443933c6ff4"
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "public_1c_cluster" {
  resource_id = "subnet-0cc2a9443933c6ff4"
  key         = "kubernetes.io/cluster/wiz-tasky-cluster"
  value       = "shared"
}

resource "aws_subnet" "private_1b" {
  vpc_id            = data.aws_vpc.wiz.id
  cidr_block        = "10.50.4.0/24"
  availability_zone = "us-east-1b"
  tags = { 
    Name = "wiz-private-1b"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/wiz-tasky-cluster" = "shared"
  }
}

resource "aws_subnet" "private_1c" {
  vpc_id            = data.aws_vpc.wiz.id
  cidr_block        = "10.50.5.0/24"
  availability_zone = "us-east-1c"
  tags = { 
    Name = "wiz-private-1c"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/wiz-tasky-cluster" = "shared"
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

# ========== OIDC + LB CONTROLLER IAM ==========
data "tls_certificate" "eks" {
  url = aws_eks_cluster.wiz_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.wiz_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_role" "lb_controller" {
  name = "wiz-alb-controller-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.wiz_cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${replace(aws_eks_cluster.wiz_cluster.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lb_controller_policy" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
}

resource "aws_iam_role_policy_attachment" "lb_controller_ec2" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "lb_controller_waf" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = "arn:aws:iam::aws:policy/AWSWAFFullAccess"
}

# ========== PREVENTATIVE CONTROL: WAF ==========
resource "aws_wafv2_web_acl" "tasky" {
  name        = "wiz-tasky-waf"
  description = "WAF for Tasky app - blocks SQLi, XSS, and rate limits"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLiRuleMetric"
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleMetric"
    }
  }

  rule {
    name     = "RateLimit"
    priority = 3
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitMetric"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "TaskyWAFMetric"
  }
}

# Output WAF ACL ARN for k8s annotation
output "waf_acl_arn" {
  value = aws_wafv2_web_acl.tasky.arn
}

output "lb_controller_role_arn" {
  value = aws_iam_role.lb_controller.arn
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

# ---------- ALERTING: Security Hub Critical Findings → Email ----------
resource "aws_sns_topic" "security_alerts" {
  name = "wiz-security-alerts"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = "rahulkuppachhi@gmail.com"
}

resource "aws_cloudwatch_event_rule" "critical_findings" {
  name        = "securityhub-critical-findings"
  description = "Alert on Security Hub CRITICAL and HIGH findings"
  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["CRITICAL", "HIGH"]
        }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "sns_alert" {
  rule      = aws_cloudwatch_event_rule.critical_findings.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.security_alerts.arn
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.security_alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.security_alerts.arn
    }]
  })
}
