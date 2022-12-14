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

  # EKS에서 애플리케이션 로드 밸런싱 문서( https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/alb-ingress.html) 에 따라 다음 태그를 설정 
  private_subnet_tags = {
    "Name"                                            = "private-subnets"
    "kubernetes.io/role/internal-elb"                 = "1"
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
  }

  public_subnet_tags = {
    "Name"                                            = "public-subnets"
    "kubernetes.io/role/elb"                          = "1"
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
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
  vpc_security_group_ids = [module.bastion_public_sg.security_group_id]
  subnet_id              = module.vpc.public_subnets[0]

  tags = local.common_tags
}

resource "aws_eip" "bastion_eip" {
  depends_on = [module.bastion_ec2_instance, module.vpc]

  vpc                       = true
  instance                  = module.bastion_ec2_instance.id
  associate_with_private_ip = module.bastion_ec2_instance.private_ip

  tags = local.common_tags
}

resource "aws_eip_association" "bastion_eip_asso" {
  instance_id   = module.bastion_ec2_instance.id
  allocation_id = aws_eip.bastion_eip.id

}

resource "null_resource" "bastion_ec2_key_copy" {
  depends_on = [module.bastion_ec2_instance, aws_eip.bastion_eip]

  # Connection Block
  connection {
    type        = "ssh"
    host        = aws_eip.bastion_eip.public_ip
    user        = "ec2-user"
    password    = ""
    private_key = file(var.private_key_file_path)
  }

  ## File Provisioner: 로컬 키 파일을 리소스에 전달 및 권한 부여
  provisioner "file" {
    source      = var.private_key_file_path
    destination = "/tmp/eks-terraform-key.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod 400 /tmp/eks-terraform-key.pem"
    ]
  }
}

###########################################################################
# EKS Cluster & Node Group's IAM Role
# Cluster
#   https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html
#   https://github.com/terraform-aws-modules/terraform-aws-eks/blob/master/main.tf
# Node Group
#   https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html
###########################################################################

resource "aws_iam_role" "eks_master_role" {
  name = "${local.name}-eks-master-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_master_role.name
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_master_role.name
}

# Node Group
resource "aws_iam_role" "eks_nodegroup_role" {
  name = "${local.name}-eks-nodegroup-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodegroup_role.name
}

###########################################################################
# EKS Cluster
#    https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster
###########################################################################
resource "aws_eks_cluster" "eks_cluster" {
  name     = local.eks_cluster_name
  role_arn = aws_iam_role.eks_master_role.arn
  version  = var.cluster_version

  # 클러스터와 연결된 VPC 의 구성 블록
  #   endpoint_private_access : API Server 와 Private Access 허용여부 (default false)
  #   endpoint_public_access : API Server 와 Public Access 허용여부 (default false)
  #   public_access_cidrs : EKS 퍼블릭 API 서버 엔드포인트에 액세스할 수 있는 CIDR 블록
  #   subnet_ids : Amazon EKS는 ENI 를 해당 서브넷에 생성하여 Worker Node 와 Kubernetes Contorl Plane 간의 통신을 허용
  #   security_group_ids :  Amazon EKS 가 생성하는 ENI 에 적용할 Security Group, 없으면 자동 생성됨
  vpc_config {
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_public_access_cidrs
    subnet_ids              = module.vpc.public_subnets
    #security_group_ids = 
  }

  # Kubernetes 서비스용 network 설정
  #    service_ipv4_cidr : Kubernetes 서비스 IP 주소를 할당할 CIDR 블록
  kubernetes_network_config {
    service_ipv4_cidr = var.cluster_service_ipv4_cidr
  }

  # Enabling Control Plane Logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Role 을 먼저 생성 필요
  depends_on = [
    aws_iam_role_policy_attachment.eks-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks-AmazonEKSVPCResourceController,
  ]
}

###########################################################################
# EKS Cluster Node Group - Public
#    https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group
###########################################################################

resource "aws_eks_node_group" "eks_ng_public" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "${local.name}-eks-ng-public"
  node_role_arn   = aws_iam_role.eks_nodegroup_role.arn
  subnet_ids      = module.vpc.public_subnets

  #ami_type       = "AL2_x86_64"
  #capacity_type  = "ON_DEMAND"
  #disk_size      = 20
  instance_types = ["t2.medium"]
  remote_access {
    ec2_ssh_key = var.bastion_instance_keypair
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  update_config {
    #max_unavailable = 1
    max_unavailable_percentage = 50
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks-AmazonEC2ContainerRegistryReadOnly,
    kubernetes_config_map_v1.aws_auth
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = {
    Name = "Public-Node-Group"
  }
}


###########################################################################
# EKS Cluster Node Group - Private
#    https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group
###########################################################################

resource "aws_eks_node_group" "eks_ng_private" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "${local.name}-eks-ng-private"
  node_role_arn   = aws_iam_role.eks_nodegroup_role.arn
  subnet_ids      = module.vpc.private_subnets

  #ami_type       = "AL2_x86_64"
  #capacity_type  = "ON_DEMAND"
  #disk_size      = 20
  instance_types = ["t2.medium"]
  remote_access {
    ec2_ssh_key = var.bastion_instance_keypair
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  update_config {
    #max_unavailable = 1
    max_unavailable_percentage = 50
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks-AmazonEC2ContainerRegistryReadOnly,
    kubernetes_config_map_v1.aws_auth
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = {
    Name = "Private-Node-Group"
  }
}


###########################################################################
# EKS IRSA
#    https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster
#    https://github.com/terraform-aws-modules/terraform-aws-eks/tree/v11.0.0/examples/irsa
########################################################################### 

# terraform-aws-modules : iam-assumable-role-with-oidc

data "aws_partition" "current" {}

data "tls_certificate" "example" {
  url = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc_provider" {
  client_id_list  = ["sts.${data.aws_partition.current.dns_suffix}"]
  thumbprint_list = [data.tls_certificate.example.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer

  tags = merge(
    {
      Name = "${var.cluster_name}-eks-irsa"
    },
    local.common_tags
  )
}

resource "aws_iam_role" "irsa_iam_role" {
  name = "${local.name}-irsa-iam-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Federated = aws_iam_openid_connect_provider.oidc_provider.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.oidc_provider.url, "https://", "")}:sub" : "system:serviceaccount:default:irsa-demo-sa"
          }
        }
      },
    ]
  })

  tags = {
    tag-key = "${local.name}-irsa-iam-role"
  }
}

resource "aws_iam_role_policy_attachment" "irsa_iam_role_policy_attach" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  role       = aws_iam_role.irsa_iam_role.name
}


###########################################################################
# EBS IRSA
###########################################################################
resource "aws_iam_role" "ebs_csi_iam_role" {
  name = "${local.name}-ebs-csi-iam-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Federated = aws_iam_openid_connect_provider.oidc_provider.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.oidc_provider.url, "https://", "")}:sub" : "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      },
    ]
  })

  tags = {
    tag-key = "${local.name}-ebs-csi-iam-role"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_iam_role_policy_attach" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_iam_role.name
}


# https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/
resource "aws_eks_addon" "ebs-csi-addon" {
  cluster_name             = aws_eks_cluster.eks_cluster.id
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.5.2-eksbuild.1"
  service_account_role_arn = aws_iam_role.ebs_csi_iam_role.arn
  tags = {
    "eks_addon" = "ebs-csi"
    "terraform" = "true"
  }

  depends_on = [
    aws_eks_cluster.eks_cluster
  ]
}

# aws eks list-addons --cluster-name IDT-dev-eks-demo-cluster
# aws eks --region ap-northeast-2 update-kubeconfig --name IDT-dev-eks-demo-cluster
# kubectl get deploy,ds,sa -l="app.kubernetes.io/name=aws-ebs-csi-driver" -n kube-system
# kubectl get sc
# aws eks list-addons --cluster-name IDT-dev-eks-demo-cluster



###########################################################################
# EKS IAM USER
###########################################################################
resource "aws_iam_user" "admin_user" {
  name          = "${local.name}-eksadmin1"
  path          = "/"
  force_destroy = true # Terraform 관리되지 않는 IAM 액세스 키, 로그인 프로파일 또는 MFA 장치가 있더라도 삭제
  tags          = local.common_tags
}

resource "aws_iam_user" "basic_user" {
  name          = "${local.name}-eksadmin2"
  path          = "/"
  force_destroy = true
  tags          = local.common_tags
}


resource "aws_iam_user_policy_attachment" "admin_user" {
  user       = aws_iam_user.admin_user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_user_policy" "basic_user_eks_policy" {
  name = "${local.name}-eks-full-access-policy"
  user = aws_iam_user.basic_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "iam:ListRoles",
          "eks:*",
          "ssm:GetParameter"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}


/*
apiVersion: v1
kind: ConfigMap
data:
  mapRoles: |
    - rolearn: arn:aws:iam::960249453675:role/IDT-dev-eks-nodegroup-role
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
  mapUsers: |
    - userarn: arn:aws:iam::960249453675:user/eksadmin1
      username: admin
      groups:
        - system:masters
    - userarn: arn:aws:iam::960249453675:user/eksadmin2
      username: admin2
      groups:
        - system:masters


metadata:
  creationTimestamp: "2022-08-23T05:51:22Z"
  name: aws-auth
  namespace: kube-system
  resourceVersion: "16367"
  uid: 2ff24fa5-e516-4c0f-a6a4-dbb90c537e43        

*/

resource "kubernetes_config_map_v1" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode(local.configmap_roles)
    mapUsers = yamlencode(local.configmap_users)
  }

  depends_on = [
    aws_eks_cluster.eks_cluster,
    aws_iam_role.eks_admin_role,
    aws_iam_role.eks_readonly_role,
    aws_iam_role.eks_developer_role,
    kubernetes_cluster_role_binding_v1.eksreadonly_clusterrolebinding,
    kubernetes_cluster_role_binding_v1.eksdeveloper_clusterrolebinding,
    kubernetes_role_binding_v1.eksdeveloper_rolebinding
  ]
}

# aws iam create-login-profile --user-name IDT-dev-eksadmin1 --password "@EKSUser101" --no-password-reset-required
# aws iam create-access-key --user-name IDT-dev-eksadmin1
# aws configure --profile IDT-dev-eksadmin1 
#      AWS Access Key ID [None]: <ACCESS KEY>
#      AWS Secret Access Key [None]: <SECRET KEY>
#      Default region name [None]: ap-northeast-2
#      Default output format [None]: json
# aws eks --region ap-northeast-2 update-kubeconfig --name IDT-dev-eks-demo-cluster --profile IDT-dev-eksadmin1
# cat $HOME/.kube/config
# kubectl get nodes
# IDT-dev-eksadmin2 도 위 과정 동일하게 테스트
# <user>/.aws/config 와  <user>/.aws/credentials 에서 테스트 정보 삭제


###########################################################################
# EKS IAM Role (Admin)
###########################################################################

# IAM Role
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "eks_admin_role" {
  name = "${local.name}-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      },
    ]
  })

  inline_policy {
    name = "eks-full-access-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = ["iam:ListRoles", "eks:*", "ssm:GetParameter"]
          Effect   = "Allow"
          Sid      = ""
          Resource = "*"
        },
      ]
    })
  }

  tags = {
    tag-key = "${local.name}-admin-role"
  }
}


# User & Group
resource "aws_iam_user" "eksadmin_guser" {
  name          = "${local.name}-eksadmin-guser"
  path          = "/"
  force_destroy = true
  tags          = local.common_tags
}


resource "aws_iam_group" "eksadmin_iam_group" {
  name = "${local.name}-eksadmins"
  path = "/"

  depends_on = [
    aws_iam_role.eks_admin_role,
  ]
}

resource "aws_iam_group_policy" "eksadmin_iam_group" {
  name  = "${local.name}-eksadmins-group-policy"
  group = aws_iam_group.eksadmin_iam_group.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Sid      = "AllowAssumeOrganizationAccountRole"
        Effect   = "Allow"
        Resource = aws_iam_role.eks_admin_role.arn
      },
    ]
  })
}


# Group Membership
resource "aws_iam_group_membership" "eksadmins_membership" {
  name = "${local.name}-admin-group-membership"

  users = [
    aws_iam_user.eksadmin_guser.name,
  ]

  group = aws_iam_group.eksadmin_iam_group.name
}


# aws iam create-login-profile --user-name IDT-dev-eksadmin-guser --password "@EKSUser101" --no-password-reset-required
# aws iam create-access-key --user-name IDT-dev-eksadmin-guser
# aws configure --profile IDT-dev-eksadmin-guser 
#      AWS Access Key ID [None]: <ACCESS KEY>
#      AWS Secret Access Key [None]: <SECRET KEY>
#      Default region name [None]: ap-northeast-2
#      Default output format [None]: json
# setx AWS_PROFILE IDT-dev-eksadmin-guser
# $ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
# aws sts assume-role --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/IDT-dev-admin-role" --role-session-name mytest
# setx AWS_ACCESS_KEY_ID RoleAccessKeyID 
# setx AWS_SECRET_ACCESS_KEY RoleSecretAccessKey
# setx AWS_SESSION_TOKEN RoleSessionToken
# aws eks --region ap-northeast-2 update-kubeconfig --name IDT-dev-eks-demo-cluster
# cat $HOME/.kube/config
# kubectl get nodes
# setx AWS_PROFILE default 
# REG delete "HKCU\Environment" /F /V "AWS_ACCESS_KEY_ID"
# REG delete "HKCU\Environment" /F /V "AWS_SECRET_ACCESS_KEY"
# REG delete "HKCU\Environment" /F /V "AWS_SESSION_TOKEN" 
# setx AWS_PROFILE default
# aws sts get-caller-identity
# <user>/.aws/config 와  <user>/.aws/credentials 에서 테스트 정보 삭제


###########################################################################
# EKS IAM Role (Readonly)
###########################################################################
resource "aws_iam_role" "eks_readonly_role" {
  name = "${local.name}-readonly-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      },
    ]
  })

  # https://docs.aws.amazon.com/eks/latest/userguide/view-kubernetes-resources.html
  inline_policy {
    name = "eks-readonly-access-policy"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "iam:ListRoles",
            "ssm:GetParameter",
            "eks:DescribeNodegroup",
            "eks:ListNodegroups",
            "eks:DescribeCluster",
            "eks:ListClusters",
            "eks:AccessKubernetesApi",
            "eks:ListUpdates",
            "eks:ListFargateProfiles",
            "eks:ListIdentityProviderConfigs",
            "eks:ListAddons",
            "eks:DescribeAddonVersions"
          ]
          Effect   = "Allow"
          Resource = "*"
        },
      ]
    })
  }

  tags = {
    tag-key = "${local.name}-eks-readonly-role"
  }
}


# User & Group
resource "aws_iam_user" "eksreadonly_guser" {
  name          = "${local.name}-eksreadonly-guser"
  path          = "/"
  force_destroy = true
  tags          = local.common_tags
}


resource "aws_iam_group" "eksreadonly_iam_group" {
  name = "${local.name}-eksreadonly"
  path = "/"

  depends_on = [
    aws_iam_role.eks_admin_role,
  ]
}

resource "aws_iam_group_policy" "eksreadonly_iam_group" {
  name  = "${local.name}-eksreadonly-group-policy"
  group = aws_iam_group.eksreadonly_iam_group.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Sid      = "AllowAssumeOrganizationAccountRole"
        Effect   = "Allow"
        Resource = aws_iam_role.eks_readonly_role.arn
      },
    ]
  })
}


# Group Membership
resource "aws_iam_group_membership" "eksreadonly_membership" {
  name = "${local.name}-readonly-group-membership"

  users = [
    aws_iam_user.eksreadonly_guser.name,
  ]

  group = aws_iam_group.eksreadonly_iam_group.name
}

# Cluster Role & Role Binding
resource "kubernetes_cluster_role_v1" "eksreadonly_clusterrole" {
  metadata {
    name = "${local.name}-eksreadonly-clusterrole"
  }

  rule {
    api_groups = [""] # core APIs 
    resources  = ["nodes", "namespaces", "pods", "events", "services", "configmaps"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "daemonsets", "statefulsets", "replicasets"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "eksreadonly_clusterrolebinding" {
  metadata {
    name = "${local.name}-eksreadonly-clusterrolebinding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.eksreadonly_clusterrole.metadata.0.name
  }
  subject {
    kind      = "Group"
    name      = "eks-readonly-group"
    api_group = "rbac.authorization.k8s.io"
  }
}

# Check ConfigMap
# aws eks --region ap-northeast-2 update-kubeconfig --name IDT-dev-eks-demo-cluster --profile default
# cat $HOME/.kube/config
# kubectl -n kube-system get configmap aws-auth -o yaml

# Check Readonly
# aws iam create-login-profile --user-name IDT-dev-eksreadonly-guser --password "@EKSUser101" --no-password-reset-required
# aws iam create-access-key --user-name IDT-dev-eksreadonly-guser
# aws configure --profile IDT-dev-eksreadonly-guser
#      AWS Access Key ID [None]: <ACCESS KEY>
#      AWS Secret Access Key [None]: <SECRET KEY>
#      Default region name [None]: ap-northeast-2
#      Default output format [None]: json
# setx AWS_PROFILE IDT-dev-eksreadonly-guser
# $ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
# aws sts assume-role --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/IDT-dev-readonly-role" --role-session-name mytestreadonly
# setx AWS_ACCESS_KEY_ID RoleAccessKeyID 
# setx AWS_SECRET_ACCESS_KEY RoleSecretAccessKey
# setx AWS_SESSION_TOKEN RoleSessionToken
# aws eks --region ap-northeast-2 update-kubeconfig --name IDT-dev-eks-demo-cluster
# cat $HOME/.kube/config
# kubectl get nodes
# kubectl get sa -n kube-system (permission denied)

# Clean
# setx AWS_PROFILE default 
# REG delete "HKCU\Environment" /F /V "AWS_ACCESS_KEY_ID"
# REG delete "HKCU\Environment" /F /V "AWS_SECRET_ACCESS_KEY"
# REG delete "HKCU\Environment" /F /V "AWS_SESSION_TOKEN" 
# setx AWS_PROFILE default
# aws sts get-caller-identity
# <user>/.aws/config 와  <user>/.aws/credentials 에서 테스트 정보 삭제


###########################################################################
# EKS IAM Role (Developer)
###########################################################################
resource "aws_iam_role" "eks_developer_role" {
  name = "${local.name}-eks-developer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      },
    ]
  })
  inline_policy {
    name = "eks-developer-access-policy"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "iam:ListRoles",
            "ssm:GetParameter",
            "eks:DescribeNodegroup",
            "eks:ListNodegroups",
            "eks:DescribeCluster",
            "eks:ListClusters",
            "eks:AccessKubernetesApi",
            "eks:ListUpdates",
            "eks:ListFargateProfiles",
            "eks:ListIdentityProviderConfigs",
            "eks:ListAddons",
            "eks:DescribeAddonVersions"
          ]
          Effect   = "Allow"
          Resource = "*"
        },
      ]
    })
  }

  tags = {
    tag-key = "${local.name}-eks-developer-role"
  }
}

resource "aws_iam_user" "eksdeveloper_user" {
  name          = "${local.name}-eksdeveloper"
  path          = "/"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_iam_group" "eksdeveloper_iam_group" {
  name = "${local.name}-eksdeveloper"
  path = "/"
}

resource "aws_iam_group_policy" "eksdeveloper_iam_group" {
  name  = "${local.name}-eksdeveloper-group-policy"
  group = aws_iam_group.eksdeveloper_iam_group.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Effect   = "Allow"
        Sid      = "AllowAssumeOrganizationAccountRole"
        Resource = "${aws_iam_role.eks_developer_role.arn}"
      },
    ]
  })
}

resource "aws_iam_group_membership" "eksdeveloper" {
  name = "${local.name}-eksdeveloper-group-membership"
  users = [
    aws_iam_user.eksdeveloper_user.name
  ]
  group = aws_iam_group.eksdeveloper_iam_group.name
}


resource "kubernetes_cluster_role_v1" "eksdeveloper_clusterrole" {
  metadata {
    name = "${local.name}-eksdeveloper-clusterrole"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "namespaces", "pods", "events", "services", "configmaps", "serviceaccounts"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "daemonsets", "statefulsets", "replicasets"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "eksdeveloper_clusterrolebinding" {
  metadata {
    name = "${local.name}-eksdeveloper-clusterrolebinding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.eksdeveloper_clusterrole.metadata.0.name
  }
  subject {
    kind      = "Group"
    name      = "eks-developer-group"
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "kubernetes_namespace_v1" "k8s_dev" {
  metadata {
    name = "dev"
  }
}

resource "kubernetes_role_v1" "eksdeveloper_role" {
  metadata {
    name      = "${local.name}-eksdeveloper-role"
    namespace = "dev"
  }

  rule {
    api_groups = ["", "extensions", "apps"]
    resources  = ["*"]
    verbs      = ["*"]
  }
  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding_v1" "eksdeveloper_rolebinding" {
  metadata {
    name      = "${local.name}-eksdeveloper-rolebinding"
    namespace = "dev"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.eksdeveloper_role.metadata.0.name
  }
  subject {
    kind      = "Group"
    name      = "eks-developer-group"
    api_group = "rbac.authorization.k8s.io"
  }
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


