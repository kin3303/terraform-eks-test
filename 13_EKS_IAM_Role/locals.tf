locals {
  owners = var.business_divsion
  environment = var.environment
  name = "${var.business_divsion}-${var.environment}"

  common_tags = {
    owners = local.owners
    environment = local.environment
  }

  eks_cluster_name = "${local.name}-${var.cluster_name}"

  oidc_provider_arn = "${aws_iam_openid_connect_provider.oidc_provider.arn}"
  oidc_provider_extracted_arn = element(split("oidc-provider/", "${aws_iam_openid_connect_provider.oidc_provider.arn}"), 1)
} 