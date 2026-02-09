variable "stage" {
  description = "Deployment stage (local, dev, prod)"
  type        = string

  validation {
    condition     = contains(["local", "dev", "prod"], var.stage)
    error_message = "Stage must be one of: local, dev, prod."
  }
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "search_service_code_path" {
  description = "Path to the SearchService Lambda function code"
  type        = string
  default     = "../../SearchService"
}

variable "publication_manager_code_path" {
  description = "Path to the PublicationManagerService Lambda function code"
  type        = string
  default     = "../../PublicationManagerService"
}
