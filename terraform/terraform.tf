terraform {
  backend "s3" {
    bucket       = "terraform-s3-backend-nguyenanh-972461217809"
    key          = "backend-locking"
    region       = "ap-southeast-1"
    use_lockfile = true
  }
}
