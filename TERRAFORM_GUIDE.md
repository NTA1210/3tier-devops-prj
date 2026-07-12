# Cẩm Nang Terraform Từ Cú Pháp Đến Quy Trình DevOps Thực Tế

Tài liệu này viết để bạn đọc được các file `.tf` trong dự án này, hiểu syntax Terraform/HCL, và biết trong thực tế DevOps engineer setup hạ tầng như thế nào. Terraform nhìn ban đầu hơi nhiều keyword, nhưng thật ra tư duy chính chỉ là:

```text
Mình mô tả hạ tầng mong muốn bằng code
        |
        v
Terraform so sánh code với hạ tầng thật
        |
        v
Terraform gọi API cloud để tạo/sửa/xóa tài nguyên
        |
        v
Terraform lưu lại trạng thái vào state
```

Trong repo này, Terraform đang được dùng để tạo AWS VPC, EC2 Jenkins/Bastion, EKS cluster, IAM role, và cài app vào Kubernetes bằng Helm như Argo CD, EBS CSI Driver, AWS Load Balancer Controller.

---

## 1. Dev Có Gõ Từng Dòng Terraform Không?

Câu trả lời thực tế: **không ai ngồi gõ từ đầu mọi thứ từng dòng như làm bài thi cả**.

Thông thường DevOps engineer làm theo kiểu này:

1. **Dùng module có sẵn**

   Ví dụ trong [terraform/vpc.tf](terraform/vpc.tf), dự án dùng module:

   ```hcl
   module "vpc" {
     source  = "terraform-aws-modules/vpc/aws"
     version = "~> 5.18.1"
   }
   ```

   Nghĩa là thay vì tự viết hàng trăm dòng để tạo VPC, subnet, route table, NAT Gateway, internet gateway, mình dùng module chuẩn từ Terraform Registry rồi truyền input vào.

2. **Copy ví dụ chính thức rồi chỉnh**

   Khi cần tạo `aws_instance`, `aws_security_group`, `helm_release`, dev thường mở Terraform Registry hoặc docs provider AWS, copy block mẫu, sau đó sửa các field như `ami`, `instance_type`, `subnet_id`, `tags`.

3. **Tách code theo file cho dễ đọc**

   Terraform không quan trọng tên file, miễn là file kết thúc bằng `.tf` trong cùng thư mục. Nhưng dev thường tách:

   ```text
   terraform.tf    -> version, provider requirement, backend
   provider.tf     -> provider config, locals
   variables.tf    -> input variables
   vpc.tf          -> network
   ec2.tf          -> EC2, security group, key pair
   eks.tf          -> EKS cluster
   outputs.tf      -> giá trị in ra sau khi apply
   ```

4. **Import hạ tầng có sẵn nếu cần**

   Nếu hạ tầng đã được tạo bằng AWS Console, dev có thể dùng `terraform import` hoặc các tool sinh code để đưa tài nguyên đó vào Terraform state/code.

5. **Code review và chạy pipeline**

   Trong team chuyên nghiệp, dev không apply trực tiếp từ máy cá nhân lên production. Thường sẽ:

   ```text
   tạo branch -> sửa .tf -> terraform fmt/validate/plan -> pull request -> review -> CI/CD apply
   ```

---

## 2. Terraform Là Gì?

Terraform là công cụ **Infrastructure as Code**. Thay vì bấm tay trên AWS Console, bạn viết code để mô tả hạ tầng.

Ví dụ bạn muốn có 1 EC2:

```hcl
resource "aws_instance" "web" {
  ami           = "ami-xxxx"
  instance_type = "t3.micro"
}
```

Terraform sẽ gọi API AWS để tạo EC2 thật.

Điểm quan trọng:

| Khái niệm | Ý nghĩa |
|---|---|
| Code `.tf` | Mô tả hạ tầng bạn muốn có |
| Provider | Plugin để Terraform nói chuyện với AWS/Azure/GCP/Kubernetes/Helm |
| Resource | Tài nguyên Terraform sẽ tạo/sửa/xóa |
| Data source | Thông tin Terraform chỉ đọc, không tạo |
| State | File ghi nhớ hạ tầng Terraform đang quản lý |
| Plan | Bản nháp cho biết Terraform sẽ làm gì |
| Apply | Thực thi thay đổi thật |
| Destroy | Xóa tài nguyên Terraform quản lý |

---

## 3. HCL Là Gì?

Terraform dùng ngôn ngữ cấu hình tên là **HCL**, viết tắt của HashiCorp Configuration Language.

HCL có 3 thành phần chính:

### 3.1. Block

Block là khối cấu hình có dấu `{}`:

```hcl
resource "aws_instance" "testinstance" {
  instance_type = "t3.medium"
}
```

Cấu trúc chung:

```hcl
block_type "label_1" "label_2" {
  argument = value
}
```

Ví dụ:

```hcl
resource "aws_instance" "testinstance" {
  ami = "ami-xxx"
}
```

Trong đó:

| Thành phần | Ví dụ | Ý nghĩa |
|---|---|---|
| `resource` | `resource` | Loại block |
| `aws_instance` | label 1 | Loại tài nguyên của provider AWS |
| `testinstance` | label 2 | Tên nội bộ trong Terraform |
| `ami = ...` | argument | Thuộc tính cấu hình |

### 3.2. Argument

Argument là dòng gán giá trị:

```hcl
region = "eu-west-1"
```

Dạng chung:

```hcl
tên_thuộc_tính = giá_trị
```

### 3.3. Expression

Expression là biểu thức tính ra giá trị:

```hcl
ami           = data.aws_ami.os_image.id
instance_type = var.instance_type
subnet_id     = module.vpc.public_subnets[0]
```

Nó có thể là string, number, list, map, object, biến, output của module, hàm, hoặc phép tính.

---

## 4. Các Kiểu Dữ Liệu Trong Terraform

Terraform không chỉ có string. Các kiểu thường gặp:

### 4.1. String

```hcl
region = "eu-west-1"
```

Chuỗi phải nằm trong dấu `"`.

### 4.2. Number

```hcl
volume_size = 20
```

### 4.3. Boolean

```hcl
enable_nat_gateway = true
wait               = false
```

Chỉ có `true` hoặc `false`, không viết `"true"` nếu field cần boolean.

### 4.4. List

```hcl
azs = ["eu-west-1a", "eu-west-1b"]
```

Truy cập phần tử bằng index, bắt đầu từ 0:

```hcl
subnet_id = module.vpc.public_subnets[0]
```

### 4.5. Map

Map là key-value:

```hcl
tags = {
  Name        = "tws-demo-ng"
  Environment = "dev"
}
```

### 4.6. Object

Object giống map nhưng có cấu trúc rõ hơn:

```hcl
app = {
  name    = "my-argo-cd"
  version = "8.1.3"
  chart   = "argo-cd"
  deploy  = 1
}
```

Trong repo này, object `app` được truyền vào module Helm ở [terraform/apps/argocd.tf](terraform/apps/argocd.tf).

---

## 5. Các Block Quan Trọng Nhất

Terraform chủ yếu xoay quanh các block sau:

```text
terraform {}  -> cấu hình Terraform, required providers, backend
provider {}   -> cấu hình cloud/provider
locals {}     -> biến nội bộ
variable {}   -> input từ bên ngoài
data {}       -> đọc tài nguyên/thông tin có sẵn
resource {}   -> tạo/sửa/xóa tài nguyên
module {}     -> gọi code Terraform đóng gói sẵn
output {}     -> in giá trị sau apply
```

---

## 6. Block `terraform`

Block `terraform` cấu hình chính Terraform engine.

Trong [terraform/terraform.tf](terraform/terraform.tf):

```hcl
terraform {
  backend "s3" {
    bucket       = "terraform-s3-backend-tws-hackathon"
    key          = "backend-locking"
    region       = "eu-west-1"
    use_lockfile = true
  }
}
```

Ý nghĩa:

| Field | Ý nghĩa |
|---|---|
| `backend "s3"` | Lưu Terraform state trên S3 |
| `bucket` | Tên S3 bucket lưu state |
| `key` | Đường dẫn/tên file state trong bucket |
| `region` | Region của bucket |
| `use_lockfile` | Dùng lock để tránh nhiều người apply cùng lúc |

### Vì Sao Cần Backend?

Nếu không có backend, Terraform lưu state ở local file `terraform.tfstate`. Làm một mình để học thì được, nhưng làm team thì nguy hiểm vì:

- Người khác không thấy state của bạn.
- Dễ apply đè nhau.
- Mất máy là mất state.
- CI/CD không biết hạ tầng hiện tại ra sao.

Backend remote như S3 giúp team dùng chung state.

Trong [terraform/apps/terraform.tf](terraform/apps/terraform.tf), bạn còn thấy:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">=2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.37.1"
    }
  }
}
```

`required_providers` nói cho Terraform biết cần tải provider nào và version nào.

---

## 7. Block `provider`

Provider là plugin để Terraform nói chuyện với nền tảng bên ngoài.

Ví dụ trong [terraform/provider.tf](terraform/provider.tf):

```hcl
provider "aws" {
  region = local.region
}
```

Nghĩa là mọi resource AWS trong thư mục này sẽ được tạo ở region `local.region`.

Trong [terraform/apps/terraform.tf](terraform/apps/terraform.tf):

```hcl
provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}
```

Ý nghĩa:

- `helm` provider dùng để cài Helm chart vào Kubernetes.
- `kubernetes` provider dùng để quản lý object Kubernetes.
- Cả hai đọc kubeconfig tại `~/.kube/config`.

Lưu ý thực tế: nếu chạy trong CI/CD, `~/.kube/config` có thể không tồn tại. Khi đó pipeline phải tạo kubeconfig trước, ví dụ bằng:

```bash
aws eks update-kubeconfig --region eu-west-1 --name tws-eks-cluster
```

---

## 8. Block `locals`

`locals` là biến nội bộ trong cùng module/thư mục Terraform.

Trong [terraform/provider.tf](terraform/provider.tf):

```hcl
locals {
  region          = "eu-west-1"
  name            = "tws-eks-cluster"
  vpc_cidr        = "10.0.0.0/16"
  azs             = ["eu-west-1a", "eu-west-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  tags = {
    example = local.name
  }
}
```

Cách dùng:

```hcl
region = local.region
name   = local.name
cidr   = local.vpc_cidr
```

Khi nào dùng `locals`?

- Giá trị dùng lặp lại nhiều nơi.
- Giá trị được tính từ biến khác.
- Tên project, region, tag chung.
- Dải subnet, naming convention.

Khác nhau giữa `locals` và `variable`:

| Loại | Dùng khi nào |
|---|---|
| `variable` | Muốn người dùng/module caller truyền giá trị từ ngoài vào |
| `locals` | Muốn tạo giá trị nội bộ để tránh lặp code |

---

## 9. Block `variable`

`variable` định nghĩa input.

Trong [terraform/variables.tf](terraform/variables.tf):

```hcl
variable "instance_type" {
  description = "Instance type for the EC2 instance"
  default     = "t3.medium"
}
```

Cách dùng:

```hcl
instance_type = var.instance_type
```

Một variable đầy đủ nên có:

```hcl
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}
```

Các cách truyền variable:

```bash
terraform apply -var="instance_type=t3.large"
```

Hoặc tạo file `terraform.tfvars`:

```hcl
instance_type = "t3.large"
```

Hoặc theo môi trường:

```bash
terraform apply -var-file="dev.tfvars"
terraform apply -var-file="prod.tfvars"
```

Best practice: nên khai báo `type` cho variable để Terraform bắt lỗi sớm.

---

## 10. Block `data`

`data` chỉ đọc thông tin có sẵn, không tạo mới.

Trong [terraform/ec2.tf](terraform/ec2.tf):

```hcl
data "aws_ami" "os_image" {
  owners      = ["099720109477"]
  most_recent = true

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/*24.04-amd64*"]
  }
}
```

Ý nghĩa:

- Tìm AMI Ubuntu 24.04 mới nhất.
- `owners = ["099720109477"]` là owner ID của Ubuntu.
- `filter` lọc AMI theo trạng thái và tên.

Cách dùng kết quả:

```hcl
ami = data.aws_ami.os_image.id
```

Công thức tham chiếu data:

```hcl
data.<loại_data>.<tên_nội_bộ>.<thuộc_tính>
```

Ví dụ:

```hcl
data.aws_ami.os_image.id
```

---

## 11. Block `resource`

`resource` là block tạo/sửa/xóa tài nguyên thật.

Ví dụ trong [terraform/ec2.tf](terraform/ec2.tf):

```hcl
resource "aws_instance" "testinstance" {
  ami                    = data.aws_ami.os_image.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.allow_user_to_connect.id]
  subnet_id              = module.vpc.public_subnets[0]
  user_data              = file("${path.module}/install_tools.sh")

  tags = {
    Name = "Jenkins-Automate"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
}
```

Giải thích từng dòng quan trọng:

| Dòng | Ý nghĩa |
|---|---|
| `resource "aws_instance" "testinstance"` | Tạo EC2, tên nội bộ là `testinstance` |
| `ami = data.aws_ami.os_image.id` | Lấy AMI từ data source |
| `instance_type = var.instance_type` | Lấy instance type từ variable |
| `key_name = aws_key_pair.deployer.key_name` | Dùng key pair được tạo trong Terraform |
| `vpc_security_group_ids = [...]` | Gắn security group |
| `subnet_id = module.vpc.public_subnets[0]` | Đặt EC2 vào public subnet đầu tiên |
| `user_data = file(...)` | Chạy script khi EC2 boot lần đầu |
| `root_block_device {}` | Cấu hình disk root |

Công thức tham chiếu resource:

```hcl
<loại_resource>.<tên_nội_bộ>.<thuộc_tính>
```

Ví dụ:

```hcl
aws_instance.testinstance.id
aws_key_pair.deployer.key_name
aws_security_group.allow_user_to_connect.id
```

---

## 12. Block `module`

Module là một gói Terraform tái sử dụng được.

Ví dụ trong [terraform/vpc.tf](terraform/vpc.tf):

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.18.1"

  name            = local.name
  cidr            = local.vpc_cidr
  azs             = local.azs
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  enable_nat_gateway = true
  single_nat_gateway = true
}
```

Ý nghĩa:

- `source`: module lấy từ đâu.
- `version`: version module.
- Các dòng còn lại là input mà module VPC hỗ trợ.

Cách lấy output từ module:

```hcl
module.vpc.vpc_id
module.vpc.public_subnets
module.vpc.private_subnets
```

Trong [terraform/eks.tf](terraform/eks.tf):

```hcl
vpc_id     = module.vpc.vpc_id
subnet_ids = module.vpc.private_subnets
```

Nghĩa là EKS dùng VPC và private subnet được tạo bởi module VPC.

### Module Local

Trong [terraform/apps/argocd.tf](terraform/apps/argocd.tf):

```hcl
module "argocd" {
  source = "../modules/alb_controller"
}
```

`source = "../modules/alb_controller"` nghĩa là module nằm trong repo của mình, không tải từ Registry.

---

## 13. Block `output`

`output` in thông tin sau khi apply.

Trong [terraform/outputs.tf](terraform/outputs.tf):

```hcl
output "vpc_id" {
  description = "The ID of the created VPC"
  value       = module.vpc.vpc_id
}
```

Sau `terraform apply`, bạn sẽ thấy output như:

```text
vpc_id = "vpc-xxxx"
```

Dùng output để:

- Xem endpoint.
- Lấy public IP.
- Truyền sang pipeline.
- Debug hạ tầng sau apply.

Ví dụ:

```hcl
output "public_ip" {
  value = aws_instance.testinstance.public_ip
}
```

---

## 14. Syntax Tham Chiếu Trong Terraform

Đây là phần cực kỳ quan trọng. Đọc Terraform chủ yếu là đọc các reference.

### 14.1. Tham chiếu variable

```hcl
var.instance_type
```

Nghĩa là lấy variable:

```hcl
variable "instance_type" {}
```

### 14.2. Tham chiếu local

```hcl
local.region
local.name
local.tags
```

Nghĩa là lấy từ:

```hcl
locals {
  region = "eu-west-1"
}
```

### 14.3. Tham chiếu resource

```hcl
aws_instance.testinstance.id
```

Dạng:

```hcl
resource_type.resource_name.attribute
```

### 14.4. Tham chiếu data source

```hcl
data.aws_ami.os_image.id
```

Dạng:

```hcl
data.data_type.data_name.attribute
```

### 14.5. Tham chiếu module output

```hcl
module.vpc.vpc_id
```

Dạng:

```hcl
module.module_name.output_name
```

### 14.6. Truy cập list bằng index

```hcl
module.vpc.public_subnets[0]
```

Lấy phần tử đầu tiên.

### 14.7. Truy cập object/map

```hcl
var.app["name"]
var.app["deploy"]
```

Hoặc:

```hcl
item.name
item.value
```

---

## 15. Nested Block

Nested block là block nằm bên trong resource/module.

Ví dụ trong EC2:

```hcl
root_block_device {
  volume_size = 20
  volume_type = "gp3"
}
```

Ví dụ trong security group:

```hcl
egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
```

Nested block không phải argument thường. Nó là cấu hình con mà provider định nghĩa.

---

## 16. `dynamic` Block

`dynamic` dùng để sinh nested block bằng vòng lặp.

Trong [terraform/ec2.tf](terraform/ec2.tf):

```hcl
dynamic "ingress" {
  for_each = [
    { description = "port 22 allow", from = 22, to = 22, protocol = "tcp", cidr = ["0.0.0.0/0"] },
    { description = "port 80 allow", from = 80, to = 80, protocol = "tcp", cidr = ["0.0.0.0/0"] },
    { description = "port 443 allow", from = 443, to = 443, protocol = "tcp", cidr = ["0.0.0.0/0"] },
    { description = "port 8080 allow", from = 8080, to = 8080, protocol = "tcp", cidr = ["0.0.0.0/0"] }
  ]

  content {
    description = ingress.value.description
    from_port   = ingress.value.from
    to_port     = ingress.value.to
    protocol    = ingress.value.protocol
    cidr_blocks = ingress.value.cidr
  }
}
```

Nếu không dùng `dynamic`, bạn phải viết 4 block `ingress` riêng.

Hiểu đơn giản:

```text
for_each có 4 item
        |
        v
Terraform sinh ra 4 block ingress
```

`ingress.value` là item hiện tại trong vòng lặp.

---

## 17. `count`

`count` dùng để tạo nhiều resource giống nhau hoặc bật/tắt resource.

Trong [terraform/modules/alb_controller/main.tf](terraform/modules/alb_controller/main.tf):

```hcl
resource "helm_release" "this" {
  count = var.app["deploy"] ? 1 : 0
}
```

Ý nghĩa:

```text
Nếu var.app["deploy"] là true/1 -> tạo 1 helm_release
Nếu false/0 -> tạo 0 helm_release
```

Đây là cách bật/tắt module bằng config.

Lưu ý: khi resource có `count`, tham chiếu thường phải có index:

```hcl
helm_release.this[0].name
```

Nếu `count = 0` mà bạn vẫn tham chiếu `[0]`, Terraform sẽ lỗi.

---

## 18. `for_each`

`for_each` cũng dùng để lặp, nhưng tốt hơn `count` khi mỗi item có key riêng.

Ví dụ minh họa:

```hcl
resource "aws_security_group_rule" "ingress" {
  for_each = {
    ssh  = 22
    http = 80
  }

  from_port = each.value
  to_port   = each.value
  protocol  = "tcp"
}
```

Trong `for_each`:

| Cú pháp | Ý nghĩa |
|---|---|
| `each.key` | Key hiện tại, ví dụ `ssh` |
| `each.value` | Value hiện tại, ví dụ `22` |

Khi nào dùng:

| Dùng | Khi |
|---|---|
| `count` | Tạo N item giống nhau hoặc bật/tắt đơn giản |
| `for_each` | Tạo nhiều item có tên/key rõ ràng |
| `dynamic` | Sinh nested block bên trong resource |

---

## 19. For Expression

For expression tạo list/map mới từ list/map cũ.

Trong [terraform/modules/alb_controller/main.tf](terraform/modules/alb_controller/main.tf):

```hcl
set = [for item in coalesce(var.set, []) : {
  "name"  = item.name
  "value" = item.value
}]
```

Ý nghĩa:

- Lấy `var.set`.
- Nếu `var.set` là null thì dùng `[]`.
- Với mỗi `item`, tạo object có `name` và `value`.

Dạng chung:

```hcl
[for item in list : item.field]
```

Ví dụ:

```hcl
ports = [for port in [80, 443] : port]
```

Map:

```hcl
{ for name, value in var.tags : name => value }
```

---

## 20. Conditional Expression

Terraform có biểu thức điều kiện:

```hcl
condition ? value_if_true : value_if_false
```

Ví dụ:

```hcl
count = var.app["deploy"] ? 1 : 0
```

Nghĩa là nếu deploy bật thì tạo 1, không thì tạo 0.

---

## 21. Hàm Thường Gặp

### 21.1. `file()`

Đọc nội dung file.

Trong [terraform/ec2.tf](terraform/ec2.tf):

```hcl
public_key = file("terra-key.pub")
user_data  = file("${path.module}/install_tools.sh")
```

### 21.2. `templatefile()`

Đọc file template và truyền biến vào.

Trong [terraform/apps/argocd.tf](terraform/apps/argocd.tf):

```hcl
values = [templatefile("${path.module}/helm-values/argocd-values.yaml", {
  serverReplicas = 1
})]
```

Nghĩa là đọc file Helm values và thay biến `${serverReplicas}` nếu file template có dùng.

### 21.3. `lookup()`

Lấy value trong map/object, nếu không có thì dùng default.

Trong [terraform/modules/alb_controller/main.tf](terraform/modules/alb_controller/main.tf):

```hcl
wait = lookup(var.app, "wait", true)
```

Nghĩa là:

```text
Nếu var.app có key wait -> dùng var.app["wait"]
Nếu không có -> dùng true
```

### 21.4. `coalesce()`

Lấy giá trị đầu tiên không null.

```hcl
coalesce(var.set, [])
```

Nếu `var.set` là null thì dùng list rỗng.

---

## 22. Biến Đặc Biệt `path.module`

`path.module` là đường dẫn tới module hiện tại.

Ví dụ:

```hcl
file("${path.module}/install_tools.sh")
```

Tốt hơn viết:

```hcl
file("install_tools.sh")
```

Vì khi module được gọi từ thư mục khác, `path.module` vẫn trỏ đúng về thư mục module.

---

## 23. Dependency Trong Terraform

Terraform tự hiểu dependency thông qua reference.

Ví dụ:

```hcl
subnet_id = module.vpc.public_subnets[0]
```

Terraform hiểu EC2 phải chờ VPC/subnet tạo xong.

```hcl
key_name = aws_key_pair.deployer.key_name
```

Terraform hiểu EC2 phải chờ key pair.

### `depends_on`

Khi Terraform không tự suy ra được dependency, bạn dùng `depends_on`.

Trong [terraform/eks.tf](terraform/eks.tf):

```hcl
data "aws_instances" "eks_nodes" {
  depends_on = [module.eks]
}
```

Ý nghĩa: chỉ query EC2 node sau khi EKS module xong.

Lưu ý: đừng lạm dụng `depends_on`. Nếu có thể tạo dependency bằng reference tự nhiên thì tốt hơn.

---

## 24. State Là Gì?

State là file Terraform dùng để ghi nhớ:

- Resource nào đang được Terraform quản lý.
- ID thật trên cloud là gì.
- Thuộc tính hiện tại của resource.
- Mapping giữa code và hạ tầng thật.

Ví dụ code:

```hcl
resource "aws_instance" "testinstance" {}
```

State sẽ ghi nhớ resource này tương ứng với EC2 thật như:

```text
i-0123456789abcdef
```

Nếu mất state, Terraform có thể không biết resource cũ là resource nào và có nguy cơ tạo trùng.

Best practice:

- Dùng remote backend như S3.
- Bật locking.
- Không commit `terraform.tfstate` lên Git.
- Không sửa state bằng tay nếu chưa hiểu rõ.

---

## 25. Terraform Plan Hiểu Như Nào?

Khi chạy:

```bash
terraform plan
```

Terraform sẽ so sánh:

```text
Code .tf + state + hạ tầng thật
```

Rồi in ra dự định thay đổi:

| Ký hiệu | Ý nghĩa |
|---|---|
| `+` | Tạo mới |
| `~` | Sửa |
| `-` | Xóa |
| `-/+` | Xóa rồi tạo lại |

Trước khi apply, luôn đọc plan. Đây là thói quen sống còn.

---

## 26. Quy Trình Lệnh Terraform Cơ Bản

Khi vào thư mục Terraform:

```bash
cd terraform
```

Chạy format:

```bash
terraform fmt -recursive
```

Tải provider/module:

```bash
terraform init
```

Kiểm tra syntax:

```bash
terraform validate
```

Xem kế hoạch:

```bash
terraform plan
```

Apply:

```bash
terraform apply
```

Xóa hạ tầng:

```bash
terraform destroy
```

Xem output:

```bash
terraform output
```

Xem state:

```bash
terraform state list
```

---

## 27. Quy Trình Setup Dự Án Terraform Từ Đầu

Một DevOps engineer thường làm như sau:

### Bước 1: Xác định kiến trúc

Ví dụ với dự án này:

```text
VPC
  |
  |-- Public Subnet
  |     |-- EC2 Jenkins/Bastion
  |
  |-- Private Subnet
        |-- EKS Control Plane/Node Groups

EKS
  |
  |-- AWS Load Balancer Controller
  |-- EBS CSI Driver
  |-- Argo CD
  |-- Prometheus/Grafana
```

### Bước 2: Tạo cấu trúc thư mục

```text
terraform/
  terraform.tf
  provider.tf
  variables.tfVVV
  vpc.tf
  ec2.tf
  eks.tf
  outputs.tf

terraform/apps/
  terraform.tf
  argocd.tf
  ebs_csi_driver.tf
  alb_controller.tf
```

### Bước 3: Viết backend/provider trước

Tạo `terraform.tf` để state không nằm local.

Tạo `provider.tf` để Terraform biết deploy ở region nào.

### Bước 4: Dựng network trước

Network thường là nền móng:

```text
VPC -> subnet -> route table -> NAT -> security group
```

Trong dự án này, phần đó được module VPC xử lý.

### Bước 5: Dựng compute

Sau network mới dựng:

- EC2 Jenkins/Bastion.
- EKS cluster.
- EKS node group.

### Bước 6: Dựng add-ons

Sau khi EKS chạy, mới cài:

- Helm provider.
- AWS Load Balancer Controller.
- EBS CSI Driver.
- Argo CD.
- Monitoring/logging.

### Bước 7: Chạy `fmt`, `validate`, `plan`, `apply`

Không apply khi chưa đọc plan.

### Bước 8: Đưa vào CI/CD

Production thường dùng pipeline:

```text
Pull Request:
  terraform fmt -check
  terraform validate
  terraform plan

Merge main:
  terraform apply
```

---

## 28. Cách Đọc Terraform Trong Repo Này

Nếu bạn mở folder `terraform/`, nên đọc theo thứ tự:

### 28.1. Đọc `terraform.tf`

Xem state lưu ở đâu.

```hcl
backend "s3" {}
```

### 28.2. Đọc `provider.tf`

Xem region, tên cluster, CIDR, subnet.

```hcl
locals {}
provider "aws" {}
```

### 28.3. Đọc `vpc.tf`

Xem network được tạo thế nào.

```hcl
module "vpc" {}
```

Output quan trọng của module này:

```hcl
module.vpc.vpc_id
module.vpc.public_subnets
module.vpc.private_subnets
```

### 28.4. Đọc `ec2.tf`

Xem Jenkins EC2:

- AMI Ubuntu lấy bằng `data`.
- Key pair lấy từ file public key.
- Security group mở port 22, 80, 443, 8080.
- EC2 chạy `install_tools.sh`.
- EIP gắn vào EC2.

### 28.5. Đọc `eks.tf`

Xem EKS:

- Cluster name là `local.name`.
- API endpoint public bị tắt, private bật.
- EKS dùng private subnet.
- Node group dùng Spot instance.
- Remote SSH access dùng key pair và security group.

### 28.6. Đọc `outputs.tf`

Xem thông tin nào được in ra sau apply.

### 28.7. Đọc `terraform/apps`

Thư mục này quản lý app cài vào cluster bằng Helm.

- `argocd.tf`: cài Argo CD.
- `ebs_csi_driver.tf`: cài AWS EBS CSI Driver.
- `alb_controller.tf`: cài AWS Load Balancer Controller.
- `kube-prom-stack.tf`: monitoring stack.
- `storageclass.tf`: storage class.

---

## 29. Những Syntax Nhìn Lạ Nhưng Rất Hay Gặp

### 29.1. Dấu `~>` trong version

```hcl
version = "~> 5.18.1"
```

Nghĩa là cho phép update patch version tương thích, nhưng không nhảy major/minor quá xa.

Ví dụ `~> 5.18.1` thường cho phép `5.18.x`, không lên `5.19` hoặc `6.0`.

### 29.2. Dấu `>=`

```hcl
version = ">=2.17"
```

Nghĩa là version từ `2.17` trở lên.

### 29.3. Comment

Terraform hỗ trợ:

```hcl
# comment một dòng
// comment một dòng
/*
comment nhiều dòng
*/
```

Trong repo này có cả `#` và `//`.

### 29.4. String interpolation

```hcl
"${path.module}/install_tools.sh"
```

Cú pháp `${...}` nhúng expression vào string.

Với Terraform mới, nếu chỉ truyền expression thì thường viết trực tiếp:

```hcl
user_data = file("${path.module}/install_tools.sh")
```

Không cần:

```hcl
user_data = "${file("install_tools.sh")}"
```

### 29.5. Escape dấu chấm trong Helm set

Trong [terraform/apps/alb_controller.tf](terraform/apps/alb_controller.tf):

```hcl
name = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
```

Helm dùng dấu `.` để hiểu nested value. Nhưng annotation Kubernetes có dấu chấm thật trong key:

```text
eks.amazonaws.com/role-arn
```

Vì vậy phải escape thành:

```text
eks\\.amazonaws\\.com/role-arn
```

---

## 30. Terraform Với AWS EKS Trong Dự Án Này

Phần EKS trong [terraform/eks.tf](terraform/eks.tf) đang làm nhiều việc:

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                    = local.name
  cluster_version                 = "1.31"
  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
}
```

Ý nghĩa:

- Dùng module EKS chính thức/cộng đồng phổ biến.
- Tạo cluster tên `tws-eks-cluster`.
- Kubernetes version `1.31`.
- Tắt public endpoint, bật private endpoint.
- Đặt node/control plane trong private subnet.

Node group:

```hcl
eks_managed_node_groups = {
  tws-demo-ng = {
    min_size     = 1
    max_size     = 3
    desired_size = 1
    capacity_type = "SPOT"
  }
}
```

Nghĩa là autoscaling node group:

- Ít nhất 1 node.
- Nhiều nhất 3 node.
- Mong muốn ban đầu 1 node.
- Dùng Spot instance để tiết kiệm chi phí.

---

## 31. Terraform Với Helm Trong Dự Án Này

Thư mục [terraform/apps](terraform/apps) dùng Terraform để cài Helm chart.

Module local [terraform/modules/alb_controller/main.tf](terraform/modules/alb_controller/main.tf) thực chất wrap resource:

```hcl
resource "helm_release" "this" {
  namespace  = var.namespace
  repository = var.repository
  name       = var.app["name"]
  version    = var.app["version"]
  chart      = var.app["chart"]
  values     = var.values
}
```

Ví dụ cài Argo CD:

```hcl
module "argocd" {
  source = "../modules/alb_controller"

  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"

  app = {
    name    = "my-argo-cd"
    version = "8.1.3"
    chart   = "argo-cd"
    deploy  = 1
  }
}
```

Hiểu đơn giản:

```text
Terraform gọi Helm
Helm tải chart từ repository
Helm cài chart vào Kubernetes cluster
```

---

## 32. File `.tfvars` Dùng Để Làm Gì?

`variables.tf` chỉ khai báo biến. `.tfvars` mới là nơi truyền giá trị cụ thể.

Ví dụ `variables.tf`:

```hcl
variable "instance_type" {
  type    = string
  default = "t3.medium"
}
```

`dev.tfvars`:

```hcl
instance_type = "t3.medium"
```

`prod.tfvars`:

```hcl
instance_type = "t3.large"
```

Chạy:

```bash
terraform plan -var-file="dev.tfvars"
terraform apply -var-file="prod.tfvars"
```

Thực tế team thường dùng nhiều môi trường:

```text
envs/
  dev/
  staging/
  prod/
```

Hoặc dùng workspace, Terragrunt, hoặc pipeline variables.

---

## 33. Workspace Là Gì?

Terraform workspace cho phép cùng một code có nhiều state khác nhau.

Lệnh:

```bash
terraform workspace list
terraform workspace new dev
terraform workspace select dev
```

Nhưng lưu ý: workspace không phải lúc nào cũng là cách tốt nhất để tách production. Nhiều team thích tách thư mục/state riêng cho từng môi trường để rõ ràng hơn.

---

## 34. Import Hạ Tầng Có Sẵn

Nếu EC2 đã tồn tại trên AWS Console, bạn có thể import vào state:

```bash
terraform import aws_instance.testinstance i-0123456789abcdef
```

Nhưng import chỉ đưa resource vào state. Bạn vẫn cần viết block `.tf` tương ứng.

Quy trình thường là:

```text
Viết block resource rỗng/đủ field cơ bản
        |
        v
terraform import
        |
        v
terraform plan
        |
        v
Bổ sung field cho code khớp hạ tầng thật
```

---

## 35. Các Lỗi Terraform Hay Gặp

### 35.1. Chưa chạy `terraform init`

Lỗi kiểu:

```text
Provider registry.terraform.io/hashicorp/aws not installed
```

Fix:

```bash
terraform init
```

### 35.2. Sai credentials AWS

Lỗi kiểu:

```text
NoCredentialProviders
```

Fix:

```bash
aws configure
aws sts get-caller-identity
```

### 35.3. Region không khớp

Trong repo này cần chú ý:

- Folder `terraform/` dùng `eu-west-1`.
- Folder `terraform/apps/` đang để `ap-south-1`.

Nếu cluster EKS ở `eu-west-1` nhưng app provider AWS lại ở `ap-south-1`, IAM/OIDC hoặc AWS resource có thể lệch region. Khi làm thật nên kiểm tra và đồng bộ region.

### 35.4. Kubeconfig chưa trỏ vào EKS

Helm provider dùng:

```hcl
config_path = "~/.kube/config"
```

Nếu kubeconfig chưa có cluster đúng, `terraform apply` trong `terraform/apps` sẽ lỗi.

Fix:

```bash
aws eks update-kubeconfig --region eu-west-1 --name tws-eks-cluster
kubectl get nodes
```

### 35.5. Security group mở quá rộng

Trong repo đang có:

```hcl
cidr_blocks = ["0.0.0.0/0"]
```

Nghĩa là mở cho toàn internet. Học/lab thì tiện, production nên giới hạn IP cụ thể, nhất là port 22.

### 35.6. Hardcode ARN/account ID/OIDC URL

Trong [terraform/eks.tf](terraform/eks.tf) và [terraform/apps](terraform/apps) có hardcode ARN/OIDC provider URL. Khi chuyển account hoặc tạo cluster mới, các giá trị này cần cập nhật.

---

## 36. Best Practices Khi Viết Terraform

1. Luôn chạy:

   ```bash
   terraform fmt -recursive
   terraform validate
   terraform plan
   ```

2. Không commit:

   ```text
   .terraform/
   terraform.tfstate
   terraform.tfstate.backup
   *.tfplan
   .terraform.lock.hcl nếu team quyết định không commit lock file
   ```

   Lưu ý: nhiều team **có commit** `.terraform.lock.hcl` để khóa provider version ổn định.

3. Không hardcode secret trong `.tf`.

   Không nên viết:

   ```hcl
   password = "my-secret-password"
   ```

   Dùng secret manager, environment variable, hoặc CI/CD secret.

4. Pin version provider/module.

   Nên có:

   ```hcl
   version = "~> 5.18.1"
   ```

5. Tách module khi code bắt đầu lặp.

6. Đặt tên resource rõ ràng.

7. Đọc kỹ plan trước khi apply.

8. Production nên apply qua pipeline, không apply tay từ laptop.

9. Dùng remote backend và locking.

10. Hạn chế dùng `depends_on` khi reference tự nhiên đã đủ.

---

## 37. Checklist Khi Bạn Muốn Thêm Một Resource Mới

Ví dụ muốn thêm S3 bucket:

1. Tìm resource trên Terraform Registry: `aws_s3_bucket`.
2. Copy example tối thiểu.
3. Dán vào file phù hợp, ví dụ `s3.tf`.
4. Đổi tên resource nội bộ:

   ```hcl
   resource "aws_s3_bucket" "app_assets" {}
   ```

5. Thêm tags theo convention.
6. Nếu cần input, thêm vào `variables.tf`.
7. Nếu cần in kết quả, thêm vào `outputs.tf`.
8. Chạy:

   ```bash
   terraform fmt -recursive
   terraform validate
   terraform plan
   ```

9. Đọc plan.
10. Apply nếu đúng.

---

## 38. Mini Cheat Sheet Syntax

```hcl
# String
name = "demo"

# Number
replicas = 2

# Boolean
enabled = true

# List
subnets = ["subnet-1", "subnet-2"]

# Map/Object
tags = {
  Name = "demo"
  Env  = "dev"
}

# Variable
instance_type = var.instance_type

# Local
region = local.region

# Resource reference
vpc_id = aws_vpc.main.id

# Data reference
ami = data.aws_ami.ubuntu.id

# Module output
subnet_id = module.vpc.public_subnets[0]

# Function
user_data = file("${path.module}/install.sh")

# Conditional
count = var.enabled ? 1 : 0

# For expression
names = [for item in var.items : item.name]

# Dynamic nested block
dynamic "ingress" {
  for_each = var.rules
  content {
    from_port = ingress.value.port
    to_port   = ingress.value.port
    protocol  = "tcp"
  }
}
```

---

## 39. Bản Đồ Tư Duy Khi Nhìn Một Dòng Terraform

Khi gặp một dòng khó hiểu, hãy tự hỏi:

```text
Dòng này đang lấy giá trị từ đâu?
```

Ví dụ:

```hcl
subnet_id = module.vpc.public_subnets[0]
```

Đọc từ phải sang trái:

```text
module.vpc        -> module tên vpc
public_subnets    -> output public_subnets của module đó
[0]               -> lấy subnet đầu tiên
subnet_id =       -> truyền subnet đó cho EC2
```

Ví dụ:

```hcl
ami = data.aws_ami.os_image.id
```

Đọc là:

```text
data aws_ami os_image tìm AMI
lấy thuộc tính id
truyền vào ami của EC2
```

Ví dụ:

```hcl
count = var.app["deploy"] ? 1 : 0
```

Đọc là:

```text
Nếu app.deploy bật thì tạo 1 resource
Nếu không thì tạo 0 resource
```

---

## 40. Lộ Trình Học Terraform Cho Repo Này

Nếu bạn đang mới học, nên đi theo thứ tự:

1. Hiểu `resource`, `variable`, `output`.
2. Hiểu `provider` và `terraform init`.
3. Hiểu `state`, `plan`, `apply`.
4. Đọc [terraform/ec2.tf](terraform/ec2.tf) trước vì dễ hiểu nhất.
5. Đọc [terraform/vpc.tf](terraform/vpc.tf) để hiểu module.
6. Đọc [terraform/eks.tf](terraform/eks.tf) để hiểu EKS.
7. Đọc [terraform/apps/argocd.tf](terraform/apps/argocd.tf) để hiểu Helm.
8. Đọc [terraform/modules/alb_controller/main.tf](terraform/modules/alb_controller/main.tf) để hiểu module local, `count`, `lookup`, `coalesce`, for expression.

Nếu bạn hiểu được các file trên, bạn đã nắm được phần Terraform rất thực chiến rồi.
