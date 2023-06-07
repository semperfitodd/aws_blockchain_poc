module "key" {
  source = "./ssh_keypair"

  name = var.environment
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.environment}_ec2_role"
  role = aws_iam_role.ec2_role.name

  tags = var.tags
}

resource "aws_iam_role" "ec2_role" {
  name = "${var.environment}_ec2_role"

  assume_role_policy = data.aws_iam_policy_document.ec2_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "AmazonManagedBlockchainFullAccess" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = data.aws_iam_policy.AmazonManagedBlockchainFullAccess.arn
}

resource "aws_iam_role_policy_attachment" "AmazonSSMManagedInstanceCore" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = data.aws_iam_policy.AmazonSSMManagedInstanceCore.arn
}

resource "aws_instance" "this" {
  ami                     = data.aws_ami.this.id
  disable_api_termination = false
  ebs_optimized           = true
  iam_instance_profile    = aws_iam_instance_profile.this.name
  instance_type           = "t3.small"
  key_name                = module.key.key_name
  monitoring              = true
  subnet_id               = module.vpc.private_subnets[0]

  vpc_security_group_ids = [aws_security_group.this.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 3
    http_tokens                 = "required"
  }

  tags        = merge(var.tags, { "Name" = var.environment })
  volume_tags = merge(var.tags, { "Name" = "${var.environment}_vol" })

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  user_data = <<-EOF
#!/bin/bash

set -x

AWS_REGION=us-east-1
MEMBER_ID=
NETWORK_ID=

# Update system packages
curl -fsSL https://rpm.nodesource.com/setup_16.x | sudo bash -
sudo yum update -y

# Install required packages
sudo yum install jq telnet emacs docker libtool libtool-ltdl-devel git nodejs -y

# Start Docker service
sudo service docker start

# Add ec2-user to docker group
sudo usermod -a -G docker ec2-user

# Install Docker Compose
sudo curl -L https://github.com/docker/compose/releases/download/1.20.0/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
sudo chmod a+x /usr/local/bin/docker-compose

# Install Go
wget https://golang.org/dl/go1.16.7.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.16.7.linux-amd64.tar.gz

# Update .bash_profile for ec2-user

sudo -u ec2-user bash -c "cat >> /home/ec2-user/.bash_profile <<EOL

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# User specific environment and startup programs
PATH=\$PATH:\$HOME/.local/bin:\$HOME/bin

# GOROOT is the location where Go package is installed on your system
export GOROOT=/usr/local/go

# GOPATH is the location of your work directory
export GOPATH=\$HOME/go
export PATH=/usr/local/go/bin:$PATH:$GOPATH/bin

# CASERVICEENDPOINT is the endpoint to reach your member's CA
export CASERVICEENDPOINT=ca.$MEMBER_ID.$NETWORK_ID.managedblockchain.$AWS_REGION.amazonaws.com:30002

# ORDERER is the endpoint to reach your network's orderer
export ORDERER=orderer.$NETWORK_ID.managedblockchain.$AWS_REGION.amazonaws.com:30001

# Update PATH so that you can access the go binary system wide
export PATH=\$GOROOT/bin:\$PATH
export PATH=\$PATH:/home/ec2-user/go/src/github.com/hyperledger/fabric-ca/bin

EOL"

# Set permissions
sudo chown ec2-user:ec2-user /home/ec2-user/.bash_profile
sudo chmod 0644 /home/ec2-user/.bash_profile

EOF

  lifecycle {
    ignore_changes = [user_data, ami]
  }
}

resource "aws_security_group" "this" {
  name        = var.environment
  description = "${var.environment} security group for EC2 and VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  tags = var.tags
}

resource "aws_security_group_rule" "egress" {
  from_port         = 0
  protocol          = -1
  security_group_id = aws_security_group.this.id
  to_port           = 0
  type              = "egress"

  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "ingress" {
  from_port         = 0
  protocol          = -1
  security_group_id = aws_security_group.this.id
  to_port           = 0
  type              = "ingress"

  self = true
}