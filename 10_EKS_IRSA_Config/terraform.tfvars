# Generic Variables
aws_region = "ap-northeast-2"
environment = "dev"
business_divsion = "IDT"


# VPC Variables 
vpc_name = "aa"
vpc_cidr_block = "10.0.0.0/16"
# [BUG-FIX] Could not launch On-Demand Instances. Unsupported - Your requested instance type (t2.medium) is not supported in your requested Availability Zone (ap-northeast-2b). Please retry your request by not specifying an Availability Zone or choosing ap-northeast-2a, ap-northeast-2c. Launching EC2 instance failed.
vpc_availability_zones = ["ap-northeast-2a", "ap-northeast-2c"]
vpc_public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]
vpc_private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
vpc_database_subnets= ["10.0.151.0/24", "10.0.152.0/24"]
vpc_create_database_subnet_group = true 
vpc_create_database_subnet_route_table = true   
vpc_enable_nat_gateway = true  
vpc_single_nat_gateway = true