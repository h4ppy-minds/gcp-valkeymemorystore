variable "env" {
  description = "Deployment environment for this TFC workspace: dev, qa, uat, or prd."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "qa", "uat", "prd"], var.env)
    error_message = "env must be one of: dev, qa, uat, prd."
  }
}

variable "manifest_file" {
  description = "Which manifest to read: memorystore-manifest-standalone.yaml, memorystore-manifest-ha.yaml, or memorystore-manifest-dr.yaml."
  type        = string
  default     = "memorystore-manifest-dr.yaml"

  validation {
    condition = contains([
      "memorystore-manifest-standalone.yaml",
      "memorystore-manifest-ha.yaml",
      "memorystore-manifest-dr.yaml"
    ], var.manifest_file)
    error_message = "manifest_file must be one of the three topology manifests in this module."
  }
}
