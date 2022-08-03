module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  # VPC Basic Detailes
  name = "my-vpc"
  cidr = "10.0.0.0/16"
  azs  = ["ap-northeast-2a", "ap-northeast-2b"]

  #Subnets
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  # NAT Gateway - Outbound communication
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  # Database Subnets
  create_database_subnet_group           = true
  create_database_subnet_route_table     = true
  create_database_nat_gateway_route      = false
  create_database_internet_gateway_route = false
  enable_dns_support                     = true
  enable_dns_hostnames                   = true
  database_subnets                       = ["10.0.151.0/24", "10.0.152.0/24"]

  # Tags
  tags = {
    "Owner" = "dnd"
    "Env"   = "dev"
  }

  vpc_tags = {
    "Name" = "vpc-dev"
  }

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
