data "google_compute_regions" "available" {
  project = var.project_id
  status  = "UP"

  lifecycle {
    postcondition {
      condition     = contains(self.names, var.location)
      error_message = "location '${var.location}' is not available for project ${var.project_id}."
    }
  }
}
data "google_compute_zones" "available_zones" {
  project = var.project_id
  region  = var.location
  status  = "UP"
}
