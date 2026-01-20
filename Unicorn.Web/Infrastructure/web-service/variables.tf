variable "stage" {
  description = "Deployment stage (local, dev, prod)"
  type        = string
  default     = "local"

  validation {
    condition     = contains(["local", "dev", "prod"], var.stage)
    error_message = "Stage must be one of: local, dev, prod."
  }
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "search_service_code_path" {
  description = "Path to the SearchService Lambda function code"
  type        = string
  default     = "../../SearchService"
}

variable "publication_manager_service_code_path" {
  description = "Path to the PublicationManagerService Lambda function code"
  type        = string
  default     = "../../PublicationManagerService"
}

locals {
  logs_retention_days = var.stage == "prod" ? 14 : 3
  is_prod            = var.stage == "prod"
  log_level          = var.stage == "prod" ? "ERROR" : "INFO"
  project_name       = "AWS Serverless Developer Experience"
}








