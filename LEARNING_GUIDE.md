# 📚 Hướng Dẫn Học & Đọc Source Code: 3-Tier E-Commerce DevOps Project

> **Dự án**: EasyShop — Next.js App + MongoDB trên AWS EKS, tự động hoá bằng Jenkins CI/CD + ArgoCD GitOps, hạ tầng quản lý bằng Terraform.

---

## 🗺️ Bức Tranh Tổng Quan — Đọc Trước Khi Làm Gì Cả

Trước khi đọc từng file, hãy hiểu **luồng dữ liệu xuyên suốt** hệ thống:

```
Developer push code
       │
       ▼
  GitHub Repo ──────────────────────────────────────┐
       │                                            │
       │ (Webhook trigger)                    ArgoCD watch
       ▼                                            │
  Jenkins Pipeline                                  │
  ├── Clone repo                                    │
  ├── Build Docker Image (Dockerfile)               │
  ├── Run Tests + Trivy Security Scan               │
  ├── Push → Docker Hub                             │
  └── Update kubernetes/ manifest (image tag)  ────┘
                                                    │
                                              ArgoCD detects
                                              manifest change
                                                    │
                                                    ▼
                                         EKS Cluster (AWS)
                                         ├── Deployment → Pods
                                         ├── Service (NodePort)
                                         └── Ingress → ALB
                                                    │
                                                    ▼
                                      easyshop.devopsdock.site
```

---

## 📂 Cấu Trúc Thư Mục — Đọc Theo Thứ Tự Này

```
3tier-e_commerce/
├── 📄 Dockerfile              ← BƯỚC 1: Hiểu app được đóng gói như nào
├── 📄 Jenkinsfile             ← BƯỚC 2: Hiểu CI pipeline
├── kubernetes/                ← BƯỚC 3: Hiểu cách deploy lên K8s
│   ├── 01-namespace.yaml
│   ├── 02-mongodb-pv.yaml
│   ├── 03-mongodb-pvc.yaml
│   ├── 04-configmap.yaml
│   ├── 05-secrets.yaml
│   ├── 06-mongodb-service.yaml
│   ├── 07-mongodb-statefulset.yaml
│   ├── 08-easyshop-deployment.yaml
│   ├── 09-easyshop-service.yaml
│   ├── 10-ingress.yaml        ← BƯỚC 4: Hiểu traffic vào như nào
│   ├── 11-hpa.yaml
│   └── 12-migration-job.yaml
├── terraform/                 ← BƯỚC 5: Hiểu hạ tầng AWS
│   ├── provider.tf
│   ├── vpc.tf
│   ├── ec2.tf
│   ├── eks.tf
│   ├── variables.tf
│   └── apps/                  ← BƯỚC 6: Hiểu cách cài tools lên EKS
│       ├── argocd.tf
│       ├── alb_controller.tf
│       ├── ebs_csi_driver.tf
│       └── kube-prom-stack.tf
└── helm-values/               ← Config chi tiết cho từng tool
    ├── argocd-values.yaml
    └── kube-prom-stack.yaml
```

---

## 🔵 BƯỚC 1 — Hiểu Dockerfile: App Được Đóng Gói Như Nào

**File**: `Dockerfile`

### Phân Tích Code

```dockerfile
# === STAGE 1: BUILD ===
FROM node:18-alpine AS builder     # Image nhỏ gọn, dùng Alpine Linux
WORKDIR /app
RUN apk add --no-cache python3 make g++   # Cần để build native modules
COPY package*.json ./
RUN npm ci                         # ci = clean install (reproducible build)
COPY . .
RUN npm run build                  # Build Next.js → .next/standalone

# === STAGE 2: PRODUCTION ===
FROM node:18-alpine AS runner      # Image MỚI, SẠCH (không có node_modules dev)
WORKDIR /app
COPY --from=builder /app/.next/standalone ./   # Chỉ copy output cần thiết
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
ENV NODE_ENV=production
ENV PORT=3000
EXPOSE 3000
CMD ["node", "server.js"]          # Next.js standalone server
```

### ⚡ Điều Quan Trọng Cần Hiểu

| Khái niệm | Giải thích |
|---|---|
| **Multi-stage build** | Stage 1 build nặng, Stage 2 chỉ chứa output → image nhỏ, bảo mật hơn |
| **npm ci vs npm install** | `npm ci` đọc package-lock.json chính xác, không thay đổi lock file |
| **standalone output** | Next.js tạo 1 file server.js duy nhất, không cần toàn bộ node_modules |
| **Alpine Linux** | Distro nhỏ (~5MB), ít attack surface hơn Ubuntu |

### ✅ Câu Hỏi Tự Kiểm Tra
- Tại sao cần 2 stage thay vì 1?
- Nếu thêm env variable `DATABASE_URL`, bạn thêm vào đâu trong Dockerfile?
- Tại sao không `COPY . .` vào stage runner?

---

## 🟠 BƯỚC 2 — Hiểu Jenkinsfile: Code Thay Đổi Thì CI Chạy Như Nào

**File**: `Jenkinsfile`

### Luồng Pipeline (7 Stage)

```
┌──────────────────────────────────────────────────────┐
│                    JENKINS PIPELINE                  │
│                                                      │
│  [1] Cleanup Workspace                               │
│       └─ Xoá file cũ từ build trước                 │
│                                                      │
│  [2] Clone Repository                                │
│       └─ git clone github.com/lax66/...  (master)   │
│                                                      │
│  [3] Build Docker Images ──── PARALLEL ────          │
│       ├─ Build Main App (Dockerfile)                 │
│       │    laxg66/easyshop-app:{BUILD_NUMBER}        │
│       └─ Build Migration (scripts/Dockerfile.migration)
│            laxg66/easyshop-migration:{BUILD_NUMBER} │
│                                                      │
│  [4] Run Unit Tests                                  │
│       └─ Chạy test suite của Next.js app            │
│                                                      │
│  [5] Security Scan with Trivy                        │
│       └─ Scan image tìm CVE vulnerabilities         │
│                                                      │
│  [6] Push Docker Images ──── PARALLEL ────           │
│       ├─ Push easyshop-app → Docker Hub              │
│       └─ Push easyshop-migration → Docker Hub        │
│                                                      │
│  [7] Update Kubernetes Manifests                     │
│       └─ Sửa image tag trong kubernetes/*.yaml       │
│       └─ git commit + push → GitHub                  │
└──────────────────────────────────────────────────────┘
```

### Phân Tích Các Biến Môi Trường

```groovy
environment {
    DOCKER_IMAGE_NAME           = 'laxg66/easyshop-app'
    DOCKER_MIGRATION_IMAGE_NAME = 'laxg66/easyshop-migration'
    DOCKER_IMAGE_TAG            = "${BUILD_NUMBER}"  // ← Tag = số build (1, 2, 3...)
    GITHUB_CREDENTIALS          = credentials('github-credentials')
    GIT_BRANCH                  = "master"
}
```

> **`BUILD_NUMBER`** là biến Jenkins tự động tăng. Build #1 → tag `laxg66/easyshop-app:1`, Build #2 → tag `:2`. Đây là cách **traceable versioning** — bạn luôn biết pod đang chạy build số mấy.

### Stage 7 — Update K8s Manifests (Cực Quan Trọng)

```groovy
stage('Update Kubernetes Manifests') {
    steps {
        script {
            update_k8s_manifests(
                imageTag: env.DOCKER_IMAGE_TAG,       // BUILD_NUMBER
                manifestsPath: 'kubernetes',           // Thư mục kubernetes/
                gitCredentials: 'github-credentials',
                gitUserName: 'Jenkins CI',
                gitUserEmail: 'misc.lucky66@gmail.com'
            )
        }
    }
}
```

**Điều này làm gì?** Hàm `update_k8s_manifests` (từ Shared Library) sẽ:
1. Tìm trong `kubernetes/08-easyshop-deployment.yaml`
2. Thay `image: laxg66/easyshop-app` → `image: laxg66/easyshop-app:42` (ví dụ build #42)
3. `git commit -m "Update image tag to 42"`
4. `git push` lên GitHub

**→ Đây là trigger cho ArgoCD!** (GitOps pattern)

### ⚡ Điều Quan Trọng Cần Hiểu

| Khái niệm | Giải thích |
|---|---|
| **`@Library('Shared') _`** | Import thư viện dùng chung (clean_ws, docker_build, etc.) |
| **`parallel`** | Build 2 images cùng lúc → tiết kiệm thời gian |
| **`credentials()`** | Lấy credential từ Jenkins Credential Store (KHÔNG hardcode password) |
| **GitOps trigger** | Jenkins không deploy trực tiếp, chỉ cập nhật Git → ArgoCD lo deploy |

### ✅ Câu Hỏi Tự Kiểm Tra
- Tại sao Jenkins không `kubectl apply` trực tiếp mà phải push Git?
- Nếu Trivy scan thấy lỗi critical CVE, pipeline có dừng lại không?
- `BUILD_NUMBER` reset về 1 khi nào?

---

## 🟡 BƯỚC 3 — Hiểu Kubernetes Manifests: Đọc Theo Số Thứ Tự

### 3.1 — Namespace `kubernetes/01-namespace.yaml`

```yaml
kind: Namespace
metadata:
  name: easyshop      # Tất cả tài nguyên đều trong "easyshop" namespace
```

> **Namespace = căn phòng riêng** trong K8s cluster. Các app khác không thấy tài nguyên trong namespace này (trừ ClusterAdmin).

---

### 3.2 — Storage cho MongoDB `kubernetes/02-mongodb-pv.yaml` + `03-mongodb-pvc.yaml`

```yaml
# PersistentVolume (PV) = ổ đĩa vật lý
kind: PersistentVolume
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce          # Chỉ 1 node được mount
  hostPath:
    path: /data/mongodb      # ← Lưu trên node disk (dev environment)
  persistentVolumeReclaimPolicy: Retain  # Xoá pod, data vẫn còn
```

> ⚠️ **Cảnh báo**: `hostPath` chỉ dùng cho **local/dev**. Production phải dùng EBS CSI Driver. Data sẽ mất nếu node bị terminate!

---

### 3.3 — ConfigMap + Secrets `kubernetes/04-configmap.yaml`

```yaml
kind: ConfigMap
data:
  MONGODB_URI: "mongodb://mongodb-service:27017/easyshop"
  # ↑ Dùng tên Service "mongodb-service" thay vì IP
  # K8s DNS tự resolve: mongodb-service.easyshop.svc.cluster.local

  NEXT_PUBLIC_API_URL: "https://easyshop.devopsdock.site/api"
  NEXTAUTH_URL:        "https://easyshop.devopsdock.site/"
```

> 💡 `mongodb-service` trong URI là **Service name** của MongoDB (`06-mongodb-service.yaml`). K8s internal DNS tự động resolve tên này thành ClusterIP. Đây là cách các pod giao tiếp với nhau trong cluster.

---

### 3.4 — MongoDB StatefulSet `kubernetes/07-mongodb-statefulset.yaml`

```yaml
kind: StatefulSet      # ← Không phải Deployment!
metadata:
  name: mongodb
spec:
  serviceName: mongodb-service   # Gắn với headless service
  replicas: 1
  template:
    spec:
      containers:
        - image: mongo:latest
          ports:
            - containerPort: 27017
          volumeMounts:
            - name: mongodb-storage
              mountPath: /data/db    # MongoDB lưu data ở đây
      volumes:
        - name: mongodb-storage
          persistentVolumeClaim:
            claimName: mongodb-pvc   # Lấy từ PVC đã tạo ở bước 3
```

> ❗ **StatefulSet vs Deployment**:
> - **Deployment**: Pod tên ngẫu nhiên (`easyshop-abc123`), stateless, có thể restart thoải mái
> - **StatefulSet**: Pod tên cố định (`mongodb-0`, `mongodb-1`), có stable network identity và persistent storage — **bắt buộc cho database!**

---

### 3.5 — App Deployment `kubernetes/08-easyshop-deployment.yaml`

```yaml
kind: Deployment
spec:
  replicas: 2          # ← 2 pod chạy song song (HA)
  selector:
    matchLabels:
      app: easyshop    # ← Label để Service tìm được các pod này
  template:
    spec:
      containers:
        - name: easyshop
          image: laxg66/easyshop-app    # ← Jenkins cập nhật tag ở đây!
          imagePullPolicy: Always        # Luôn pull image mới nhất
          ports:
            - containerPort: 3000
          envFrom:
            - configMapRef:
                name: easyshop-config   # Inject tất cả key từ ConfigMap
            - secretRef:
                name: easyshop-secrets  # Inject tất cả secret
          resources:
            requests:
              memory: "256Mi"
              cpu: "200m"
            limits:
              memory: "512Mi"
              cpu: "500m"

          # === 3 LOẠI HEALTH CHECK ===
          startupProbe:      # Pod có khởi động xong không? (300s timeout)
            httpGet:
              path: /
              port: 3000
            failureThreshold: 30
            periodSeconds: 10

          readinessProbe:    # Pod có sẵn sàng nhận traffic không?
            httpGet:
              path: /
              port: 3000
            initialDelaySeconds: 20
            periodSeconds: 15

          livenessProbe:     # Pod còn sống không? (restart nếu fail)
            httpGet:
              path: /
              port: 3000
            initialDelaySeconds: 25
            periodSeconds: 20
```

> ❗ **3 loại Probe**:
> - `startupProbe`: Cho app thời gian khởi động. Nếu fail sau 30×10=300s → kill pod
> - `readinessProbe`: Nếu fail → **remove pod khỏi load balancer**, traffic không vào
> - `livenessProbe`: Nếu fail → **restart pod** tự động

---

### 3.6 — HPA (Auto-scaling) `kubernetes/11-hpa.yaml`

```yaml
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef:
    kind: Deployment
    name: easyshop
  minReplicas: 2     # Tối thiểu 2 pods (luôn HA)
  maxReplicas: 5     # Tối đa 5 pods
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70    # CPU > 70% → scale up
```

---

## 🔴 BƯỚC 4 — Hiểu Service & Ingress: Traffic Vào App Như Nào

### 4.1 — Service Expose Pod `kubernetes/09-easyshop-service.yaml`

```yaml
kind: Service
spec:
  type: NodePort        # ← Expose ra ngoài cluster qua port của Node
  ports:
    - port: 80          # Port của Service (cluster internal)
      targetPort: 3000  # Port của Pod (container)
      nodePort: 30000   # Port trên Node IP (30000-32767)
  selector:
    app: easyshop       # ← Khớp với label ở Deployment!
```

**Luồng traffic qua Service:**
```
Internet → NodeIP:30000 → Service:80 → Pod:3000 (easyshop container)
```

**Cơ chế load balancing của Service:**
```
              ┌─────────────────┐
Request ─────►│  easyshop-svc   │
              │   (ClusterIP)   │
              └────────┬────────┘
                       │ kube-proxy phân phối ngẫu nhiên
              ┌────────┴────────┐
              ▼                 ▼
        [Pod-1: 3000]    [Pod-2: 3000]
```

---

### 4.2 — Ingress / ALB `kubernetes/10-ingress.yaml`

```yaml
kind: Ingress
metadata:
  annotations:
    # ↓ AWS ALB Controller đọc các annotation này để config ALB
    alb.ingress.kubernetes.io/scheme: internet-facing
    # ↑ ALB public (internet-facing) vs internal

    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:876997124628:...
    # ↑ SSL Certificate từ ACM (HTTPS)

    alb.ingress.kubernetes.io/target-type: ip
    # ↑ ALB route thẳng đến Pod IP (không qua NodePort)

    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}, {"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    # ↑ HTTP → HTTPS redirect tự động

    kubernetes.io/ingress.class: alb
    # ↑ Dùng AWS ALB (không phải nginx/traefik)

spec:
  rules:
  - host: easyshop.devopsdock.site    # ← Domain name
    http:
      paths:
      - path: /                        # Tất cả request
        backend:
          service:
            name: easyshop-service     # → Forward đến Service
            port:
              number: 80
```

**Toàn bộ luồng traffic từ internet vào pod:**
```
User browser
    │
    ▼ DNS lookup: easyshop.devopsdock.site → ALB DNS name
    │
    ▼
[Route53 / DNS Provider]
    │
    ▼
[AWS Application Load Balancer] ← Tạo tự động bởi ALB Ingress Controller
    │  - HTTPS:443 (SSL termination tại đây)
    │  - HTTP:80 → redirect 443
    │
    ▼
[easyshop-service: NodePort 80]
    │  kube-proxy load balance
    ├──────────────────────►[Pod-1: port 3000]
    └──────────────────────►[Pod-2: port 3000]
```

---

## 🟢 BƯỚC 5 — Hiểu Terraform: Hạ Tầng AWS Được Tạo Như Nào

### 5.1 — Thứ Tự Apply Terraform

```
provider.tf     → Khai báo AWS provider, locals (region, CIDR, etc.)
    │
    ▼
vpc.tf          → Tạo VPC, Subnets, NAT Gateway, Internet Gateway
    │
    ▼
ec2.tf          → Tạo Jenkins Server EC2 (trong public subnet)
    │
    ▼
eks.tf          → Tạo EKS Cluster + Node Group (trong private subnet)
    │
    ▼
apps/           → Cài tools lên EKS (ArgoCD, ALB Controller, etc.)
```

---

### 5.2 — VPC Architecture `terraform/vpc.tf`

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"

  name = local.name      # "tws-eks-cluster"
  cidr = "10.0.0.0/16"  # Toàn bộ VPC

  azs             = ["eu-west-1a", "eu-west-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]   # Jenkins, ALB
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]   # EKS Nodes

  enable_nat_gateway = true    # Nodes private vẫn ra internet qua NAT
  single_nat_gateway = true    # 1 NAT duy nhất (tiết kiệm chi phí)

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1    # ← ALB biết subnet nào là public
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}
```

**Topology:**
```
┌──────────────────── VPC: 10.0.0.0/16 ────────────────────────┐
│                                                               │
│  ┌─── Public Subnet (10.0.1.0/24) ─────────────────────┐    │
│  │  Jenkins EC2  │  NAT Gateway  │ ALB                  │◄───┼── Internet
│  └──────────────────────────────────────────────────────┘    │   Gateway
│                       │                                       │
│  ┌─── Private Subnet (10.0.3.0/24) ────────────────────┐    │
│  │  EKS Node-1  │  EKS Node-2                          │────►NAT
│  └──────────────────────────────────────────────────────┘    │
└───────────────────────────────────────────────────────────────┘
```

---

### 5.3 — Jenkins EC2 `terraform/ec2.tf`

```hcl
resource "aws_instance" "testinstance" {
  ami           = data.aws_ami.os_image.id  # Ubuntu 24.04 LTS (auto-select latest)
  instance_type = var.instance_type          # t3.medium (từ variables.tf)
  subnet_id     = module.vpc.public_subnets[0]   # Public subnet
  user_data     = file("install_tools.sh")   # ← Script chạy khi EC2 khởi động

  tags = { Name = "Jenkins-Automate" }
}

resource "aws_eip" "jenkins_server_ip" {
  instance = aws_instance.testinstance.id   # Elastic IP cố định cho Jenkins
}
```

**`install_tools.sh` tự động cài:**
- Jenkins (Java 17)
- Docker (+ add jenkins user vào docker group)
- Trivy (security scanner)
- AWS CLI
- Helm

---

### 5.4 — EKS Cluster `terraform/eks.tf`

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "tws-eks-cluster"
  cluster_version = "1.31"

  cluster_endpoint_public_access  = false   # API server KHÔNG public
  cluster_endpoint_private_access = true    # Chỉ trong VPC

  # ← Jenkins EC2 / IAM User được phép dùng kubectl
  access_entries = {
    example = {
      principal_arn = "arn:aws:iam::876997124628:user/terraform"
      policy_associations = {
        example = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        }
      }
    }
  }

  # Addon mặc định
  cluster_addons = {
    coredns    = { most_recent = true }   # DNS nội bộ cluster
    kube-proxy = { most_recent = true }   # Network proxy
    vpc-cni    = { most_recent = true }   # Pod networking
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets   # Nodes trong private subnet

  eks_managed_node_groups = {
    tws-demo-ng = {
      min_size     = 1
      max_size     = 3
      desired_size = 1
      instance_types = ["t3.large"]
      capacity_type  = "SPOT"        # ← SPOT instances (rẻ hơn 70%)
      disk_size      = 35            # GB
    }
  }
}
```

> ⚠️ **SPOT Instances** rẻ hơn nhưng AWS có thể reclaim bất cứ lúc nào. Production nên dùng thêm On-Demand hoặc có Pod Disruption Budget.

---

## 🟣 BƯỚC 6 — Hiểu ArgoCD: GitOps Sync Manifest Như Nào

### 6.1 — ArgoCD Được Cài Bằng Terraform + Helm

**File**: `terraform/apps/argocd.tf`

```hcl
module argocd {
  source     = "../modules/alb_controller"   # Module dùng helm_release
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"

  app = {
    name    = "my-argo-cd"
    chart   = "argo-cd"
    version = "8.1.3"
  }
  values = [templatefile("${path.module}/helm-values/argocd-values.yaml", {
    serverReplicas = 1
  })]
}
```

### 6.2 — Cách ArgoCD Sync Hoạt Động

```
                     GITOPS LOOP

  ┌─────────────────────────────────────────────┐
  │  GitHub Repo                                │
  │  kubernetes/08-easyshop-deployment.yaml    │◄─── Jenkins push
  │  → image: laxg66/easyshop-app:42           │
  └──────────────────┬──────────────────────────┘
                     │
                     │ ArgoCD poll every 3 minutes
                     │ (hoặc webhook trigger)
                     │
                     ▼
  ┌─────────────────────────────────────────────┐
  │  ArgoCD Controller                          │
  │  1. So sánh Git state vs Cluster state      │
  │  2. Phát hiện: image tag đã thay đổi!      │
  │  3. Apply manifest mới lên EKS              │
  └──────────────────┬──────────────────────────┘
                     │
                     ▼
  ┌─────────────────────────────────────────────┐
  │  EKS Cluster                                │
  │  kubectl apply -f kubernetes/               │
  │  → Rolling update: pod cũ → pod mới        │
  └─────────────────────────────────────────────┘
```

### 6.3 — ArgoCD Application Resource (tạo thủ công hoặc qua UI)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: easyshop
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/lax66/tws-e-commerce-app_hackathon.git
    targetRevision: master
    path: kubernetes/          # ← Thư mục chứa manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: easyshop
  syncPolicy:
    automated:
      prune: true        # Xoá resource không còn trong Git
      selfHeal: true     # Tự sửa nếu ai đó manual edit cluster
```

---

## ⚪ BƯỚC 7 — Hiểu ALB Controller: Ingress Tạo Load Balancer Như Nào

**File**: `terraform/apps/alb_controller.tf`

```hcl
# 1. Tạo IAM Policy cho ALB Controller
resource "aws_iam_policy" "alb_policy" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = file("iam_policy.json")    # ← 500+ dòng policy JSON
}

# 2. Tạo IAM Role với OIDC (Workload Identity - IRSA)
module "iam_assumable_role_with_oidc" {
  source = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"

  role_name        = "AmazonEKSLoadBalancerControllerRole"
  provider_url     = "oidc.eks.ap-south-1.amazonaws.com/..."  # OIDC endpoint của EKS
  role_policy_arns = [aws_iam_policy.alb_policy.arn]
}

# 3. Cài ALB Controller bằng Helm
module alb_controller {
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"

  app = {
    name    = "aws-load-balancer-controller"
    chart   = "aws-load-balancer-controller"
    version = "1.13.3"
  }

  set = [{
    name  = "serviceAccount.annotations.eks.amazonaws.com/role-arn"
    value = module.iam_assumable_role_with_oidc.this_iam_role_arn
    # ↑ ServiceAccount của controller assume IAM Role này (IRSA)
  }]
}
```

**Cách ALB Controller hoạt động:**

```
1. Apply kubernetes/10-ingress.yaml
         │
         ▼
2. ALB Controller phát hiện Ingress resource mới
         │
         ▼
3. Controller gọi AWS API tạo Application Load Balancer
   - Scheme: internet-facing
   - Target group: Pod IPs (target-type: ip)
   - Listener: 443 (HTTPS) + 80 (redirect)
   - SSL cert từ ACM
         │
         ▼
4. ALB được tạo, DNS: xxx.us-east-1.elb.amazonaws.com
         │
         ▼
5. Trỏ DNS easyshop.devopsdock.site → ALB DNS name
```

---

## 🔁 BƯỚC 8 — Ghép Toàn Bộ Luồng: End-to-End Flow

```
═══════════════════════════════════════════════════════
PHASE 1: INFRASTRUCTURE (chạy 1 lần)
═══════════════════════════════════════════════════════

cd terraform/
terraform init && terraform apply
→ Tạo: VPC, Jenkins EC2, EKS Cluster

cd terraform/apps/
terraform init && terraform apply
→ Cài: ArgoCD, ALB Controller, EBS CSI, Prometheus/Grafana

═══════════════════════════════════════════════════════
PHASE 2: CI/CD (mỗi lần có code change)
═══════════════════════════════════════════════════════

DEV push code → GitHub
    ↓ (webhook)
Jenkins khởi động pipeline
    ↓
Build Docker image (multi-stage)
    ↓
Test + Trivy scan
    ↓
Push image: laxg66/easyshop-app:BUILD_NUMBER → Docker Hub
    ↓
Update kubernetes/08-easyshop-deployment.yaml (image tag)
    ↓
git push → GitHub

═══════════════════════════════════════════════════════
PHASE 3: GITOPS DELIVERY (tự động)
═══════════════════════════════════════════════════════

ArgoCD detect Git change
    ↓
Compare: desired state (Git) vs actual state (cluster)
    ↓
kubectl apply kubernetes/*.yaml
    ↓
Kubernetes rolling update:
  - Tạo pod mới với image:BUILD_NUMBER
  - readinessProbe pass → add vào Service
  - Xoá pod cũ (zero downtime)
    ↓
Traffic từ ALB → Service → Pod mới ✅
```

---

## 🔍 Những Điều Cần Chú Ý Khi Đọc Code

### ⚠️ Security Issues (Học Từ Đây)

| Vị trí | Issue | Cách Đúng |
|---|---|---|
| `kubernetes/04-configmap.yaml` dòng 11 | NEXTAUTH_SECRET lưu plain text trong ConfigMap | Nên dùng K8s Secret hoặc AWS Secrets Manager |
| `terraform/eks.tf` dòng 9 | Node SG allow SSH `0.0.0.0/0` | Giới hạn IP cụ thể hoặc dùng SSM Session Manager |
| `kubernetes/02-mongodb-pv.yaml` dòng 10 | `hostPath` cho MongoDB | Production: dùng EBS CSI Driver + StorageClass |
| `terraform/apps/alb_controller.tf` dòng 18 | OIDC provider URL hardcode region | Nên lấy từ EKS module output |

### 💡 Pattern Học Được

| Pattern | Ví dụ trong Project | Tại Sao Dùng |
|---|---|---|
| **GitOps** | Jenkins push Git, ArgoCD pull & apply | Audit trail, rollback dễ, declarative |
| **Multi-stage Docker** | `Dockerfile` stage builder/runner | Image nhỏ, không chứa build tools |
| **Separate Config** | ConfigMap + Secret tách khỏi image | Một image, nhiều môi trường |
| **Health Probes** | startup/readiness/liveness | Zero-downtime deployment |
| **HPA** | CPU 70% → scale up | Tự động scaling theo load |
| **IRSA** | ALB Controller IAM Role via OIDC | Pod có IAM quyền, không cần hardcode key |
| **Private Subnet EKS** | Nodes không có public IP | Security: nodes không bị expose trực tiếp |
| **StatefulSet DB** | MongoDB dùng StatefulSet | Stable identity + persistent storage |

---

## 📝 Lộ Trình Học Đề Xuất (3 Tuần)

### Tuần 1: Foundation — Docker & Kubernetes
- [ ] Đọc `Dockerfile` → Hiểu multi-stage build
- [ ] Đọc `kubernetes/` theo thứ tự `01-namespace.yaml` → `12-migration-job.yaml`
- [ ] Tự vẽ diagram quan hệ giữa các K8s resources (Deployment → Service → Ingress)
- [ ] Thực hành: Câu hỏi — Service selector `app: easyshop` match với label nào trong Deployment?

### Tuần 2: CI/CD & IaC
- [ ] Đọc `Jenkinsfile` → Trace từng stage, chú ý stage cuối
- [ ] Đọc `terraform/provider.tf` → `vpc.tf` → `ec2.tf` → `eks.tf` (theo thứ tự dependency)
- [ ] Hiểu Terraform modules, state, và `local.name` được define ở đâu
- [ ] Thực hành: Tìm file nào define `local.name` và `local.vpc_cidr`

### Tuần 3: Advanced — ArgoCD, ALB, Observability
- [ ] Đọc `terraform/apps/` → Hiểu cách cài tool lên K8s bằng Helm via Terraform
- [ ] Đọc `helm-values/argocd-values.yaml` → Hiểu cấu hình ArgoCD
- [ ] Đọc `helm-values/kube-prom-stack.yaml` → Hiểu Prometheus + Grafana stack
- [ ] Trace toàn bộ luồng từ `git push` đến user nhận HTTP response

---

## 🎯 Câu Hỏi Kiểm Tra Cuối Cùng

1. **Jenkins**: Tại sao stage "Update K8s Manifests" là stage cuối, không phải "Push Docker Image"?

2. **Docker**: Nếu bạn thêm `RUN npm install some-package` vào Stage 2 (runner), điều gì xảy ra so với thêm vào Stage 1?

3. **K8s Probes**: Nếu `readinessProbe` fail, pod có bị restart không? Traffic có đến pod đó không?

4. **K8s DNS**: Tại sao `MONGODB_URI` dùng `mongodb-service` thay vì IP address? Điều gì xảy ra nếu pod MongoDB restart và IP thay đổi?

5. **Ingress**: Nếu xoá annotation `alb.ingress.kubernetes.io/certificate-arn`, điều gì xảy ra với HTTPS?

6. **Terraform**: `capacity_type = "SPOT"` có ý nghĩa gì? Rủi ro và cách handle khi SPOT bị reclaim?

7. **ArgoCD**: Nếu ai đó chạy `kubectl edit deployment easyshop -n easyshop` và tăng replicas từ 2 → 5, ArgoCD `selfHeal: true` sẽ làm gì?

8. **IRSA**: Tại sao ALB Controller cần IAM Role? Nếu không có IRSA, pod có thể gọi AWS API không?

9. **StatefulSet**: Tại sao MongoDB dùng StatefulSet thay vì Deployment? Pod `mongodb-0` restart, tên pod có thay đổi không?

10. **GitOps Flow**: Vẽ lại toàn bộ luồng từ khi dev `git push` đến khi user trình duyệt nhận được trang web mới.

---

## 🗂️ Bảng Tổng Hợp File Quan Trọng

| File | Vai Trò | Đọc Khi |
|---|---|---|
| `Dockerfile` | Build image production | Muốn hiểu app được đóng gói |
| `Jenkinsfile` | CI pipeline definition | Muốn hiểu automation flow |
| `kubernetes/08-easyshop-deployment.yaml` | App deployment config | Muốn hiểu pod spec, probes, resources |
| `kubernetes/10-ingress.yaml` | ALB routing rules | Muốn hiểu traffic vào như nào |
| `terraform/provider.tf` | VPC CIDR, region, locals | Bắt đầu đọc Terraform |
| `terraform/eks.tf` | EKS cluster config | Muốn hiểu cluster setup |
| `terraform/apps/argocd.tf` | ArgoCD Helm install | Muốn hiểu GitOps tool setup |
| `terraform/apps/alb_controller.tf` | ALB Controller + IRSA | Muốn hiểu ingress → AWS ALB |
| `helm-values/argocd-values.yaml` | ArgoCD fine-tuning | Advanced: muốn customize ArgoCD |
| `terraform/install_tools.sh` | Jenkins EC2 bootstrap | Muốn hiểu EC2 được cài gì |

---

*Tài liệu này dựa trên source code thực tế của dự án. Cập nhật lần cuối: 2026-07-11*
