terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name - used as a name prefix and state key prefix"
  type        = string
}

variable "tf_state_bucket" {
  description = "S3 bucket used for Terraform state AND Lambda zip artifact"
  type        = string
  default     = ""
}

variable "lambda_zip_key" {
  description = "S3 key for the Lambda zip artifact"
  type        = string
  default     = ""
}

variable "public_key" {
  description = "SSH public key"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# IAM role for the Lambda function
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------------------------------------------------------
# Lambda function (zip sourced from S3)
# ---------------------------------------------------------------------------

locals {
  zip_key = var.lambda_zip_key != "" ? var.lambda_zip_key : "${var.project_name}/lambda.zip"
}

resource "aws_lambda_function" "app" {
  count = var.tf_state_bucket != "" ? 1 : 0

  function_name = "${var.project_name}-app"
  role          = aws_iam_role.lambda_exec.arn

  s3_bucket = var.tf_state_bucket
  s3_key    = local.zip_key

  runtime     = "python3.11"
  handler     = "lambda_handler.handler"
  timeout     = 30
  memory_size = 512

  environment {
    variables = {
      APP_ENV = "production"
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

# ---------------------------------------------------------------------------
# Lambda Function URL (public, no auth)
# ---------------------------------------------------------------------------

resource "aws_lambda_function_url" "app" {
  count = var.tf_state_bucket != "" ? 1 : 0

  function_name      = aws_lambda_function.app[0].function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
    max_age           = 86400
  }
}

resource "aws_lambda_permission" "allow_public_url" {
  count = var.tf_state_bucket != "" ? 1 : 0

  statement_id           = "AllowPublicFunctionURL"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.app[0].function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "function_url" {
  description = "Public Lambda Function URL"
  value       = var.tf_state_bucket != "" ? aws_lambda_function_url.app[0].function_url : ""
}

output "function_name" {
  description = "Lambda function name"
  value       = var.tf_state_bucket != "" ? aws_lambda_function.app[0].function_name : ""
}