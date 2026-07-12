# Terraform Runbook

Guide này ghi lại các bước chạy Terraform cho project này trên AWS region `ap-southeast-1`.

Kiến trúc chạy theo 2 tầng:

```text
terraform/
  -> tạo VPC, EC2 Jenkins/Bastion, EKS cluster, node group

terraform/apps/
  -> cài add-ons vào EKS bằng Helm/Kubernetes provider
     ví dụ: Argo CD, ALB Controller, EBS CSI Driver, kube-prometheus-stack
```

## 0. Chuẩn Bị AWS Credentials

Nếu bạn dùng profile `terraform-lab` bằng `aws login`, AWS CLI có thể dùng được profile nhưng Terraform provider có thể không đọc trực tiếp được. Cách ổn định hiện tại là export credentials ra environment variables:

```bash
eval "$(aws configure export-credentials --profile terraform-lab --format env)"
unset AWS_PROFILE
aws sts get-caller-identity
```

Lệnh `aws sts get-caller-identity` phải trả về account AWS trước khi chạy Terraform.

Nếu dùng access key thường, có thể cấu hình profile:

```bash
aws configure --profile terraform-lab
```

## 1. Tạo SSH Key Cho EC2

Terraform dùng file `terra-key.pub` để tạo AWS key pair:

```hcl
public_key = file("terra-key.pub")
```

Nếu chưa có key, chạy trong folder `terraform/`:

```bash
ssh-keygen -t ed25519 -f terra-key -N ""
chmod 400 terra-key
```

Kết quả:

```text
terra-key      -> private key, không commit lên Git
terra-key.pub  -> public key, Terraform dùng để tạo aws_key_pair
```

## 2. Tạo S3 Backend Bucket

Terraform backend S3 không tự tạo bucket. Bucket phải tồn tại trước khi chạy `terraform init`.

Backend hiện nằm trong `terraform.tf`:

```hcl
backend "s3" {
  bucket       = "terraform-s3-backend-nguyenanh-972461217809"
  key          = "backend-locking"
  region       = "ap-southeast-1"
  use_lockfile = true
}
```

Tạo bucket:

```bash
aws s3api create-bucket \
  --bucket terraform-s3-backend-nguyenanh-972461217809 \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1
```

Bật versioning để bảo vệ Terraform state:

```bash
aws s3api put-bucket-versioning \
  --bucket terraform-s3-backend-nguyenanh-972461217809 \
  --versioning-configuration Status=Enabled
```

Chặn public access:

```bash
aws s3api put-public-access-block \
  --bucket terraform-s3-backend-nguyenanh-972461217809 \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Kiểm tra bucket:

```bash
aws s3api head-bucket \
  --bucket terraform-s3-backend-nguyenanh-972461217809
```

## 3. Chạy Terraform Root

Đứng trong folder `terraform/`:

```bash
cd terraform
```

Format code:

```bash
terraform fmt -recursive
```

Khởi tạo Terraform và S3 backend:

```bash
terraform init
```

Nếu cần ép Terraform cấu hình lại backend:

```bash
terraform init -reconfigure
```

Kiểm tra syntax/config:

```bash
terraform validate
```

Xem plan trước khi tạo resource:

```bash
terraform plan
```

Apply hạ tầng chính:

```bash
terraform apply
```

Tầng này tạo:

```text
VPC
Public/private subnets
NAT Gateway
EC2 Jenkins-Automate
Bastion Host
EKS cluster
EKS managed node group
Security groups
Elastic IP
```

## 4. Kết Nối Kubectl Vào EKS

Sau khi `terraform apply` root xong, update kubeconfig:

```bash
aws eks --region ap-southeast-1 update-kubeconfig --name tws-eks-cluster
```

Kiểm tra:

```bash
kubectl get nodes
```

Lưu ý: trong `eks.tf`, EKS API endpoint đang private:

```hcl
cluster_endpoint_public_access  = false
cluster_endpoint_private_access = true
```

Nếu bạn chạy từ laptop ngoài VPC mà không có VPN/Bastion phù hợp, `kubectl`, Helm, và `terraform/apps` có thể không kết nối được cluster.

## 5. Chạy Terraform Apps

Sau khi EKS đã chạy và kubeconfig trỏ đúng cluster:

```bash
cd apps
terraform fmt -recursive
terraform init
terraform validate
terraform plan
terraform apply
```

Tầng này cài:

```text
AWS Load Balancer Controller
EBS CSI Driver
Argo CD
kube-prometheus-stack
StorageClass
```

`terraform/apps` dùng:

```text
AWS provider        -> tạo IAM policy/role cho add-ons
Helm provider       -> cài Helm chart vào EKS
Kubernetes provider -> tạo Kubernetes resources như StorageClass
```

## 6. Login Argo CD

Lấy password admin ban đầu:

```bash
export ARGOCD_ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
```

Login Argo CD:

```bash
argocd login argocd.devopsdock.site \
  --username admin \
  --password "$ARGOCD_ADMIN_PASSWORD" \
  --insecure
```

Kiểm tra app:

```bash
argocd app list
```

Xem log app:

```bash
argocd app logs easyshop -n default
argocd app logs mongo-app -n default
```

## 7. Lỗi Thường Gặp

### No valid credential sources found

Terraform không đọc được AWS credentials.

Chạy lại:

```bash
eval "$(aws configure export-credentials --profile terraform-lab --format env)"
unset AWS_PROFILE
aws sts get-caller-identity
terraform plan
```

### S3 bucket does not exist

Backend bucket chưa được tạo. Tạo bucket ở bước 2 trước khi `terraform init`.

### file terra-key.pub does not exist

Bạn chưa tạo SSH public key. Chạy bước 1.

### kubectl hoặc Helm không connect được EKS

Kiểm tra kubeconfig:

```bash
aws eks --region ap-southeast-1 update-kubeconfig --name tws-eks-cluster
kubectl config current-context
kubectl get nodes
```

Nếu cluster endpoint private, cần chạy từ trong VPC hoặc có đường mạng private tới EKS.

