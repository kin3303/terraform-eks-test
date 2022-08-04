module "vpc" {
  source = "terraform-aws-modules/vpc/aws" 
  version = "3.14.2"
  
  # VPC Basic Detailes
  name = "${local.name}-${var.vpc_name}"
  cidr = var.vpc_cidr_block
  azs  = var.vpc_availability_zones

  #Subnets
  public_subnets  =  var.vpc_public_subnets
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
  tags  = local.common_tags
  vpc_tags  = local.common_tags

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

/*
resource "aws_instance" "foo" {
  ami           = "ami-0ff8a91507f77f867"
  instance_type = "t1.2xlarge" # invalid type!
}
*/