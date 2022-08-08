
###########################################################################
# General Variables
###########################################################################
variable "aws_region" {
  description = "AWS Region to use"
  type    = string
  default = "ap-northeast-2"
}
 
variable "environment" {
  description = "Environment Variable used as a prefix"
  type = string
  default = "dev"
}

variable "business_divsion" {
  description = "Business Division"
  type = string
  default = "idt"
}

###########################################################################
# VPC Variables
###########################################################################
# VPC Name
variable "vpc_name" {
  description = "VPC Name"
  type = string 
  default = "myvpc"
}

variable "vpc_cidr_block" {
  description = "VPC CIDR Block"
  type = string 
  default = "10.0.0.0/16"
}

variable "vpc_availability_zones" {
  description = "VPC Availability Zones"
  type = list(string)
  default = ["ap-northeast-2a", "ap-northeast-2b"]
}

variable "vpc_public_subnets" {
  description = "VPC Public Subnets"
  type = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "vpc_private_subnets" {
  description = "VPC Private Subnets"
  type = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "vpc_database_subnets" {
  description = "VPC Database Subnets"
  type = list(string)
  default = ["10.0.151.0/24", "10.0.152.0/24"]
}

variable "vpc_create_database_subnet_group" {
  description = "VPC Create Database Subnet Group"
  type = bool
  default = true 
}

variable "vpc_create_database_subnet_route_table" {
  description = "VPC Create Database Subnet Route Table"
  type = bool
  default = true   
}

variable "vpc_enable_nat_gateway" {
  description = "Whether enable NAT Gateways for Private Subnets Outbound Communication"
  type = bool
  default = true  
}

variable "vpc_single_nat_gateway" {
  description = "Whether enable only single NAT Gateway"
  type = bool
  default = true
}

###########################################################################
# Bastion Host Variables
###########################################################################
# AWS EC2 Instance Type
variable "bastion_instance_type" {
  description = "EC2 Instance Type"
  type = string
  default = "t3.micro"  
}

# AWS EC2 Instance Key Pair
variable "bastion_instance_keypair" {
  description = "AWS EC2 Key pair that need to be associated with EC2 Instance"
  type = string
  default = "eks-terraform-key"
}

variable "private_key_file_path" {
  description = "Private key file to handle eks worker node from bastion host"
  type = string
  default = "D:/Key/eks-terraform-key.pem"
}


###########################################################################
# EKS Cluster Variables
###########################################################################
variable "cluster_name" {
  description = "EKS cluster name"
  type = string
  default = "eks-cluster"
}
