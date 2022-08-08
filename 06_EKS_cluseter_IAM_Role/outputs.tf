###########################################################################
# VPC 
###########################################################################

# VPC ID
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

# VPC CIDR blocks
output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

# VPC Private Subnets
output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

# VPC Public Subnets
output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

# VPC NAT gateway Public IP
output "nat_public_ips" {
  description = "List of public Elastic IPs created for AWS NAT Gateway"
  value       = module.vpc.nat_public_ips
}

# VPC AZs
output "azs" {
  description = "A list of availability zones spefified as argument to this module"
  value       = module.vpc.azs
}


###########################################################################
# Bastion Host 
###########################################################################

# Security Group
output "bastion_sequrity_group_id" {
  value = module.bastion_public_sg.security_group_id
}

# Bastion Instance ID
output "bastion_host_id" {
  value = module.bastion_ec2_instance.id
}


# Bastion Instance IP Check
output "bastion_host_public_ip" {
  value = module.bastion_ec2_instance.public_ip
}

output "bastion_host_eip" {
  value = aws_eip.bastion_eip.public_ip
}




