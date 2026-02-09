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

variable "lambda_code_path" {
  description = "Path to the Lambda function code"
  type        = string
  default     = "../../ApprovalsService"
}
