# Used by locals.tf to validate that var.location is actually available to this
# project (regions can be restricted by org policy / resource location constraints).
data "google_compute_regions" "available_regions" {
  project = var.project_id
}

# Used by locals.tf to auto-select (or validate) a zone when
# zone_distribution_mode = SINGLE_ZONE.
data "google_compute_zones" "available_zones" {
  project = var.project_id
  region  = var.location
}

# Host project number/ID — used for service-agent references (e.g. CMEK,
# customer-managed CA IAM bindings) that need the numeric project ID.
data "google_project" "host_project" {
  project_id = var.project_id
}

# Used by locals.tf to auto-select (or validate) a zone for the SECONDARY
# (DR) instance when zone_distribution_mode = SINGLE_ZONE. Only queried
# when cross-region replication is actually enabled.
data "google_compute_zones" "available_secondary_zones" {
  count   = var.enable_cross_region_replication ? 1 : 0
  project = var.project_id
  region  = var.secondary_location
}

data "google_compute_network" "shared_vpc_net" {
  count   = var.psc_connectivity_mode == "SHARED_VPC" ? 1 : 0
  project = var.shared_vpc_host_project
  name    = var.shared_vpc_network_name
}
