variable "project_id" {
  type        = string
  description = "Project ID"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_id))
    error_message = "Only lowercase letters, numbers and hyphens allowed."
  }
  default = "valkeyhubhost-500604"
}
variable "location" {
  description = "GCP region where the Memorystore instance will be created (e.g., us-central1, us-east1)"
  type        = string
  default     = "us-central1"
  validation {
    condition     = contains(data.google_compute_regions.available_regions, var.location)
    error_message = "Location must be a valid US GCP region supported by Memorystore for Valkey."
  }
}
variable "zone" {
  description = "Optional zone for SINGLE_ZONE distribution. Leave null to let GCP auto-select."
  type        = string
  default     = null
}
