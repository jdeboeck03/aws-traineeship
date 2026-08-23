resource "aws_dynamodb_table" "this" {
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "title"

  attribute {
    name = "title"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = var.name
  }
}
