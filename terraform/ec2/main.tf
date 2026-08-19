# AWS publishes the current recommended Amazon Linux 2023 build under this SSM parameter, so we
# never have to hardcode an AMI ID that goes stale as new builds ship every few weeks.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Generate an SSH key pair locally and upload the public key to AWS.
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "${var.name}-key"
  public_key = tls_private_key.this.public_key_openssh
}

# Save the private key to disk so you can SSH in.
resource "local_sensitive_file" "private_key" {
  filename        = "${var.name}-key.pem"
  content         = tls_private_key.this.private_key_pem
  file_permission = "0400"
}

# Only create a security group when none are passed in — allows standalone use without a VPC module.
resource "aws_security_group" "this" {
  count       = length(var.security_group_ids) == 0 ? 1 : 0
  name        = "${var.name}-sg"
  description = "Allow SSH inbound"

  ingress {
    description = "SSH"
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

  tags = {
    Name = "${var.name}-sg"
  }
}

resource "aws_instance" "this" {
  # SSM parameter values are marked sensitive by default — nonsensitive() unmarks it so the AMI ID
  # is still visible in plan/apply output.
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023_ami.value)
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.this.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.this[0].id]
  associate_public_ip_address = true
  iam_instance_profile        = var.iam_instance_profile

  tags = {
    Name = var.name
  }
}
