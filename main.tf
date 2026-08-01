terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_iam_role" "labrole" {
  name = "LabRole"
}

data "aws_caller_identity" "current" {}

resource "aws_secretsmanager_secret" "news_api_key" {
  name = "news-api-key"
}

resource "aws_lambda_function" "hello" {
  function_name = "capstone-phase1"

  role = data.aws_iam_role.labrole.arn

  runtime = "python3.12"
  handler = "lambda_function.lambda_handler"

  filename         = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip")

  timeout = 10
}

resource "aws_apigatewayv2_api" "cti_api" {
  name          = "cti-news-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.cti_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.hello.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "news_route" {
  api_id    = aws_apigatewayv2_api.cti_api.id
  route_key = "GET /news"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.cti_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.cti_api.execution_arn}/*/*"
}

resource "aws_dynamodb_table" "news_table" {
  name         = "cti-news-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "news_id"

  attribute {
    name = "news_id"
    type = "S"
  }
}

resource "aws_s3_bucket" "frontend" {
  bucket = "cti-news-dashboard-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_policy" "frontend_public_read" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = "index.html"
  etag         = filemd5("index.html")
  content_type = "text/html"
}

resource "aws_s3_object" "style_css" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "style.css"
  source       = "style.css"
  etag         = filemd5("style.css")
  content_type = "text/css"
}

resource "aws_s3_object" "script_js" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "script.js"
  source       = "script.js"
  etag         = filemd5("script.js")
  content_type = "application/javascript"
}

output "api_endpoint" {
  value = "${aws_apigatewayv2_api.cti_api.api_endpoint}/news"
}

output "labrole_arn" {
  value = data.aws_iam_role.labrole.arn
}

output "website_url" {
  value = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}