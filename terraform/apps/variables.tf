variable "aws_region" {
  description = "AWS region where the EKS cluster exists"
  type        = string
  default     = "ap-southeast-1"
}

variable "cluster_name" {
  description = "EKS cluster name where Helm charts will be installed"
  type        = string
  default     = "tws-eks-cluster"
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

locals {
  oidc_provider_url = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  vpc_id            = data.aws_eks_cluster.this.vpc_config[0].vpc_id
}
