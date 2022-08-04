###########################################################################
# VPC 
###########################################################################

data "aws_availability_zones" "available" {
  state         = "available"
  exclude_names = ["ap-northeast-2c, ap-northeast-2d"]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.14.2"

  # VPC Basic Detailes
  name = "${local.name}-${var.vpc_name}"
  cidr = var.vpc_cidr_block
  azs  = data.aws_availability_zones.available.names

  #Subnets
  public_subnets  = var.vpc_public_subnets
  private_subnets = var.vpc_private_subnets

  # NAT Gateway - Outbound communication
  enable_nat_gateway     = var.vpc_enable_nat_gateway
  single_nat_gateway     = var.vpc_single_nat_gateway
  one_nat_gateway_per_az = false

  # Database Subnets
  create_database_subnet_group           = var.vpc_create_database_subnet_group
  create_database_subnet_route_table     = var.vpc_create_database_subnet_route_table
  create_database_nat_gateway_route      = false
  create_database_internet_gateway_route = false
  enable_dns_support                     = true
  enable_dns_hostnames                   = true
  database_subnets                       = var.vpc_database_subnets

  # Tags
  tags     = local.common_tags
  vpc_tags = local.common_tags

  private_subnet_tags = {
    "Name" = "private-subnets"
  }

  public_subnet_tags = {
    "Name" = "public-subnets"
  }

  database_subnet_tags = {
    "Name" = "database-subnets"
  }
}

###########################################################################
# Bastion Host
###########################################################################

# Bastion Host SG
module "bastion_public_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.9.0"

  name        = "${local.name}-public-bastion-sg"
  description = "Security group for bastion host SSH communication"
  vpc_id      = module.vpc.vpc_id

  use_name_prefix = "false" # 해당 옵션을 false 시키지 않을 경우, 그룹이름 뒤에 고유 넘버링이 부착되어 생성됨

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "ssh"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "all"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  tags = local.common_tags
}


# Bastion Host Instance
data "aws_ami" "amazon_linux2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-*-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}


module "bastion_ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = " ~> 3.6.0"

  name = "${local.name}-bastion-ec2-instance"

  ami           = data.aws_ami.amazon_linux2.id
  instance_type = var.bastion_instance_type
  key_name      = var.bastion_instance_keypair
  #monitoring   = true
  vpc_security_group_ids = [ module.bastion_public_sg.security_group_id ]
  subnet_id              = module.vpc.public_subnets[0]

  tags = local.common_tags
}

resource "aws_eip" "bastion_eip" {
  instance = module.bastion_ec2_instance.id
  vpc      = true
  depends_on = [ module.bastion_ec2_instance, module.vpc ]
  tags = local.common_tags
}

###########################################################################
# tflint
###########################################################################

/*
resource "aws_instance" "foo" {
  ami           = "ami-0ff8a91507f77f867"
  instance_type = "t1.2xlarge" # invalid type!
}
*/
