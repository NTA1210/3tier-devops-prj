variable "aws_region" {
  description = "AWS region where resources will be provisioned"
  default     = "ap-southeast-1"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  default     = "ami-085f9c64a9b75eed5"
}

variable "jenkins_instance_type" {
  description = "Instance type for the Jenkins EC2 instance"
  default     = "t3.medium"
}

variable "bastion_instance_type" {
  description = "Instance type for the Bastion EC2 instance"
  default     = "t3.micro"
}

variable "eks_node_instance_types" {
  description = "Instance types for the EKS managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "my_enviroment" {
  description = "Instance type for the EC2 instance"
  default     = "dev"
}
