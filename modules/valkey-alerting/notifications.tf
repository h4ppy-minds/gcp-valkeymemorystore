############################################
# One notification channel per unique address across appteam_emails and
# platformteam_emails combined (see local.notification_channel_specs) —
# every address gets exactly one channel regardless of which team's list
# it came from, so a duplicate entry in both sets doesn't create two
# channels for the same address.
#
# Created in var.project_id because notification channels are project-scoped
# and the alert policies in alert_policies.tf live in var.project_id too — a
# channel in a different project simply cannot be attached to these
# policies, regardless of who "owns" the email address.
############################################

resource "google_monitoring_notification_channel" "email" {
  for_each     = local.notification_channel_specs
  project      = var.project_id
  display_name = each.value.display_name
  type         = "email"
  labels = {
    email_address = each.value.email
  }
}
