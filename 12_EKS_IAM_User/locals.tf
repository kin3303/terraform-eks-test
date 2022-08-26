# Common Local Variables
locals {
  owners = var.business_divsion
  environment = var.environment
  name = "${var.business_divsion}-${var.environment}"

  common_tags = {
    owners = local.owners
    environment = local.environment
  }

  eks_cluster_name = "${local.name}-${var.cluster_name}"

  oidc_provider_arn = aws_iam_openid_connect_provider.oidc_provider.arn
  oidc_provider_extracted_arn = element(split("oidc-provider/", aws_iam_openid_connect_provider.oidc_provider.arn), 1)
}

# Kubernetes Local Variables

/*
apiVersion: v1
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

kind: ConfigMap
metadata:
  creationTimestamp: "2022-08-23T05:51:22Z"
  name: aws-auth
  namespace: kube-system
  resourceVersion: "16367"
  uid: 2ff24fa5-e516-4c0f-a6a4-dbb90c537e43        
*/
locals {
  configmap_roles = [
    {
      rolearn = aws_iam_role.eks_nodegroup_role.arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = ["system:bootstrappers", "system:nodes"]
    },
  ]
  configmap_users = [
    {
      userarn = aws_iam_user.admin_user.arn
      username = aws_iam_user.admin_user.name
      groups = ["system:masters"]
    },
    {
      userarn = aws_iam_user.basic_user.arn
      username = aws_iam_user.basic_user.name
      groups = ["system:masters"]
    },
  ]
}
