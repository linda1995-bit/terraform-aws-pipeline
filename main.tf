# -------------------------------------------------------
# VPC
# -------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name        = "github-terraform-vpc-test"
    Environment = "dev"
  }
}


# -------------------------------------------------------
# Restrict the default Security Group
# No inbound or outbound rules are defined
# -------------------------------------------------------

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "restricted-default-sg"
  }
}


# -------------------------------------------------------
# Get current AWS account information
# Used when creating the KMS key policy
# -------------------------------------------------------

data "aws_caller_identity" "current" {}


# -------------------------------------------------------
# KMS key for encrypting CloudWatch VPC Flow Logs
# -------------------------------------------------------

resource "aws_kms_key" "cloudwatch_logs" {
  description         = "KMS key for VPC Flow Logs in CloudWatch"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "EnableAccountAdministration"
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }

        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"

        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }

        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]

        Resource = "*"

        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc/flow-logs"
          }
        }
      }
    ]
  })

  tags = {
    Name = "vpc-flow-logs-kms"
  }
}


# -------------------------------------------------------
# CloudWatch Log Group
# Stores the VPC Flow Logs
# Retain logs for 1 year
# Encrypt logs using KMS
# -------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.cloudwatch_logs.arn
}


# -------------------------------------------------------
# IAM Role used by the VPC Flow Logs service
# -------------------------------------------------------

resource "aws_iam_role" "vpc_flow_logs" {
  name = "vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}


# -------------------------------------------------------
# Permissions for VPC Flow Logs to write to CloudWatch
# -------------------------------------------------------

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]

        Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
      },
      {
        Effect = "Allow"

        Action = [
          "logs:DescribeLogGroups"
        ]

        Resource = "*"
      }
    ]
  })
}


# -------------------------------------------------------
# Enable VPC Flow Logs
# Capture both accepted and rejected traffic
# -------------------------------------------------------

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn

  depends_on = [
    aws_iam_role_policy.vpc_flow_logs
  ]
}