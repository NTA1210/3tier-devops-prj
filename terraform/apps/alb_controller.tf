resource "aws_iam_policy" "alb_policy" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  path   = "/"
  policy = file("iam_policy.json")
}
module "iam_assumable_role_with_oidc" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "~> 2.0"

  create_role = true

  role_name = "AmazonEKSLoadBalancerControllerRole"

  tags = {
    Role = "role-alb-controller"
  }

  provider_url = local.oidc_provider_url

  role_policy_arns = [
    aws_iam_policy.alb_policy.arn,
  ]
}

module "alb_controller" {
  source = "../modules/alb_controller"

  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"

  app = {
    name          = "aws-load-balancer-controller"
    description   = "aws-load-balancer-controller"
    version       = "1.13.3"
    chart         = "aws-load-balancer-controller"
    force_update  = true
    wait          = false
    recreate_pods = false
    deploy        = true
  }
  values = [templatefile("${path.module}/helm-values/alb_controller-1.13.3.yaml", {
    replicaCount = 1
  })]

  set = [
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.iam_assumable_role_with_oidc.this_iam_role_arn
    },
    {
      name  = "clusterName"
      value = var.cluster_name
    },
    {
      name  = "region"
      value = var.aws_region
    },
    {
      name  = "vpcId"
      value = local.vpc_id
    }
  ]

}
