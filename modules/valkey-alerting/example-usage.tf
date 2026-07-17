module "valkey_alerts" {
  source = "./valkey-alerts-module"

  project_id  = "my-project"
  instance_id = google_memorystore_instance.shared_instance.instance_id
  region      = "us-central1"

  # Service team is in a different project — omit this if they share yours
  service_project_id = "my-service-project"

  platform_critical_emails = ["platform-oncall@example.com"]
  platform_warning_emails  = ["platform-team@example.com"]

  service_team_critical_emails = ["service-oncall@example.com"]
  service_team_warning_emails  = ["service-team@example.com"]

  # Optional — override defaults if your workload's baseline differs
  cpu_warning_threshold               = 0.8
  cpu_critical_threshold              = 0.95
  connected_clients_warning_threshold = 6000
  rejected_connections_threshold      = 1
}
