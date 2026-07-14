############################################
# PSC Network — supports both connectivity modes
#
# AUTO mode: Memorystore auto-creates the forwarding rule/endpoint inside
#            a consumer VPC that this module creates for you.
# USER mode: This module creates the consumer VPC(s), forwarding rule(s),
#            and reserved IP(s) itself, then explicitly registers each
#            connection with the instance.
#
# In BOTH modes, the network resources belong to the CONSUMER project
# (local.effective_consumer_project_id) — not the host project. The
# resource names below (carried over from Google's own examples) use
# "producer" in the label, which is misleading: the network you see here
# is always YOUR consumer-side VPC, never Google's actual producer
# infrastructure. See README.md for a full explanation of this naming.
############################################

data "google_project" "consumer_project" {
  project_id = local.effective_consumer_project_id
}

############################################
# AUTO mode
############################################

resource "google_compute_network" "auto_producer_net" {
  count                   = var.psc_connectivity_mode == "AUTO" ? 1 : 0
  project                 = local.effective_consumer_project_id
  name                    = "${var.instance_id}-net"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "auto_producer_subnet" {
  count         = var.psc_connectivity_mode == "AUTO" ? 1 : 0
  project       = local.effective_consumer_project_id
  name          = "${var.instance_id}-subnet"
  ip_cidr_range = "10.0.0.248/29" # small range — only used for PSC IP allocation
  region        = var.location
  network       = google_compute_network.auto_producer_net[0].id
}

resource "google_network_connectivity_service_connection_policy" "auto_policy" {
  count         = var.psc_connectivity_mode == "AUTO" ? 1 : 0
  project       = local.effective_consumer_project_id
  name          = "${var.instance_id}-scp"
  location      = var.location
  service_class = "gcp-memorystore"
  network       = google_compute_network.auto_producer_net[0].id

  psc_config {
    subnetworks = [google_compute_subnetwork.auto_producer_subnet[0].id]
  }
}

############################################
# AUTO mode — SECONDARY (DR only)
#
# A full, independent copy of the AUTO networking stack, in
# secondary_location. PSC connections are strictly regional, so the
# secondary cannot share the primary's network/subnet/policy even though
# both may live in the same consumer project.
############################################

resource "google_compute_network" "auto_producer_net_secondary" {
  count                   = (var.psc_connectivity_mode == "AUTO" && var.enable_cross_region_replication) ? 1 : 0
  project                 = local.effective_consumer_project_id
  name                    = "${var.instance_id}-dr-net"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "auto_producer_subnet_secondary" {
  count         = (var.psc_connectivity_mode == "AUTO" && var.enable_cross_region_replication) ? 1 : 0
  project       = local.effective_consumer_project_id
  name          = "${var.instance_id}-dr-subnet"
  ip_cidr_range = "10.0.1.248/29"
  region        = var.secondary_location
  network       = google_compute_network.auto_producer_net_secondary[0].id
}

resource "google_network_connectivity_service_connection_policy" "auto_policy_secondary" {
  count         = (var.psc_connectivity_mode == "AUTO" && var.enable_cross_region_replication) ? 1 : 0
  project       = local.effective_consumer_project_id
  name          = "${var.instance_id}-dr-scp"
  location      = var.secondary_location
  service_class = "gcp-memorystore"
  network       = google_compute_network.auto_producer_net_secondary[0].id

  psc_config {
    subnetworks = [google_compute_subnetwork.auto_producer_subnet_secondary[0].id]
  }
}

############################################
# USER mode
############################################

resource "google_compute_network" "user_net" {
  for_each                = var.psc_connectivity_mode == "USER" ? var.user_networks : {}
  project                 = local.effective_consumer_project_id
  name                    = "${var.instance_id}-${each.key}-net"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "user_subnet" {
  for_each      = var.psc_connectivity_mode == "USER" ? var.user_networks : {}
  project       = local.effective_consumer_project_id
  name          = "${var.instance_id}-${each.key}-subnet"
  ip_cidr_range = each.value.subnet_cidr
  region        = var.location
  network       = google_compute_network.user_net[each.key].id
}

# One reserved IP per (consumer network × service attachment). A single
# instance can expose multiple service attachments (e.g. discovery + one
# per shard); each needs its own endpoint if clients in that network must
# reach it.
resource "google_compute_address" "user_endpoint_ip" {
  for_each     = local.user_network_attachments
  project      = local.effective_consumer_project_id
  name         = "${var.instance_id}-${each.key}-ip"
  region       = var.location
  subnetwork   = google_compute_subnetwork.user_subnet[each.value.network_key].id
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
}

# One forwarding rule per (consumer network × service attachment). This IS
# the PSC endpoint — creating it sends a connection request toward the
# instance's service attachment, which starts out PENDING until registered
# below.
#
# TWO-PHASE APPLY REQUIRED ON FIRST CREATE:
#   psc_attachment_details only exists once the instance itself has been
#   created, but this forwarding rule needs an entry from that list as its
#   target. On a from-scratch apply, run:
#     terraform apply -target=google_memorystore_instance.shared-instance
#     terraform apply
#   Google's own USER-mode tutorials describe this same two-step sequence —
#   it is inherent to the mechanism, not a gap in this module.
resource "google_compute_forwarding_rule" "user_fr" {
  for_each                = local.user_network_attachments
  project                 = local.effective_consumer_project_id
  name                    = "${var.instance_id}-${each.key}-fr"
  region                  = var.location
  network                 = google_compute_network.user_net[each.value.network_key].id
  ip_address              = google_compute_address.user_endpoint_ip[each.key].id
  load_balancing_scheme   = "" # required empty string for PSC forwarding rules
  target                  = google_memorystore_instance.shared-instance.psc_attachment_details[each.value.attachment_index].service_attachment
  allow_psc_global_access = true
}

# Registers each manually created connection with the instance, in the
# HOST project — this is what flips each connection from PENDING to
# ACTIVE. One `desired_user_created_endpoints` block per consumer network;
# within it, one `connections` block per service attachment reachable from
# that network, each containing a nested `psc_connection` block.
resource "google_memorystore_instance_desired_user_created_endpoints" "user_registration" {
  count   = var.psc_connectivity_mode == "USER" ? 1 : 0
  project = var.project_id
  name    = google_memorystore_instance.shared-instance.instance_id
  region  = var.location

  dynamic "desired_user_created_endpoints" {
    for_each = var.user_networks
    content {
      dynamic "connections" {
        for_each = local.psc_attachment_indices
        content {
          psc_connection {
            psc_connection_id  = google_compute_forwarding_rule.user_fr["${desired_user_created_endpoints.key}-${connections.value}"].psc_connection_id
            ip_address         = google_compute_address.user_endpoint_ip["${desired_user_created_endpoints.key}-${connections.value}"].address
            forwarding_rule    = google_compute_forwarding_rule.user_fr["${desired_user_created_endpoints.key}-${connections.value}"].id
            network            = google_compute_network.user_net[desired_user_created_endpoints.key].id
            service_attachment = google_memorystore_instance.shared-instance.psc_attachment_details[connections.value].service_attachment
          }
        }
      }
    }
  }
}

############################################
# USER mode — SECONDARY (DR only)
#
# Mirrors the primary's USER-mode block exactly, targeting the
# secondary instance's own service attachments in secondary_location.
# Requires the same two-phase apply as the primary (create secondary
# instance first via -target, then apply again), keyed off the secondary
# instance instead of the primary.
############################################

resource "google_compute_network" "user_net_secondary" {
  for_each                = length(local.secondary_user_network_attachments) > 0 ? var.user_networks : {}
  project                 = local.effective_consumer_project_id
  name                    = "${var.instance_id}-dr-${each.key}-net"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "user_subnet_secondary" {
  for_each      = length(local.secondary_user_network_attachments) > 0 ? var.user_networks : {}
  project       = local.effective_consumer_project_id
  name          = "${var.instance_id}-dr-${each.key}-subnet"
  ip_cidr_range = each.value.subnet_cidr
  region        = var.secondary_location
  network       = google_compute_network.user_net_secondary[each.key].id
}

resource "google_compute_address" "user_endpoint_ip_secondary" {
  for_each     = local.secondary_user_network_attachments
  project      = local.effective_consumer_project_id
  name         = "${var.instance_id}-dr-${each.key}-ip"
  region       = var.secondary_location
  subnetwork   = google_compute_subnetwork.user_subnet_secondary[each.value.network_key].id
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
}

resource "google_compute_forwarding_rule" "user_fr_secondary" {
  for_each                = local.secondary_user_network_attachments
  project                 = local.effective_consumer_project_id
  name                    = "${var.instance_id}-dr-${each.key}-fr"
  region                  = var.secondary_location
  network                 = google_compute_network.user_net_secondary[each.value.network_key].id
  ip_address              = google_compute_address.user_endpoint_ip_secondary[each.key].id
  load_balancing_scheme   = ""
  target                  = google_memorystore_instance.secondary[0].psc_attachment_details[each.value.attachment_index].service_attachment
  allow_psc_global_access = true
}

resource "google_memorystore_instance_desired_user_created_endpoints" "user_registration_secondary" {
  count   = (var.psc_connectivity_mode == "USER" && var.enable_cross_region_replication) ? 1 : 0
  project = var.project_id
  name    = google_memorystore_instance.secondary[0].instance_id
  region  = var.secondary_location

  dynamic "desired_user_created_endpoints" {
    for_each = var.user_networks
    content {
      dynamic "connections" {
        for_each = local.psc_attachment_indices
        content {
          psc_connection {
            psc_connection_id  = google_compute_forwarding_rule.user_fr_secondary["${desired_user_created_endpoints.key}-${connections.value}"].psc_connection_id
            ip_address         = google_compute_address.user_endpoint_ip_secondary["${desired_user_created_endpoints.key}-${connections.value}"].address
            forwarding_rule    = google_compute_forwarding_rule.user_fr_secondary["${desired_user_created_endpoints.key}-${connections.value}"].id
            network            = google_compute_network.user_net_secondary[desired_user_created_endpoints.key].id
            service_attachment = google_memorystore_instance.secondary[0].psc_attachment_details[connections.value].service_attachment
          }
        }
      }
    }
  }
}
