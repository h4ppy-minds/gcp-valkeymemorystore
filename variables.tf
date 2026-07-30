variable "env" {
  description = "Deployment environment for this TFC workspace: dev, qa, uat, or prd. Selects which environments.<env> block in default.json applies, and filters onboarding request files to this environment only."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "qa", "uat", "prd"], var.env)
    error_message = "env must be one of: dev, qa, uat, prd."
  }
}
