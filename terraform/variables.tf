variable "aws_access_key_id" {
  description = "AWS Access Key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS Secret Access Key"
  type        = string
  sensitive   = true
}

variable "s3_bucket_name" {
  description = "Nom du bucket S3"
  type        = string
}

variable "jwt_secret" {
  description = "Clé secrète pour signer les JWT"
  type        = string
  sensitive   = true
}

variable "image_registry" {
  description = "Préfixe du registry (ex: europe-west1-docker.pkg.dev/PROJECT/tp-cloud)"
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "Tag des images Docker"
  type        = string
  default     = "latest"
}