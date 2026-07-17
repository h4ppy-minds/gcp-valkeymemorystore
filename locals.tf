locals {
  # Set project ID based on env variable in TFC workspace
  provider_project_id = (
    var.env == "prd" ? "valkeyhubhost-500604" :                        # Replace with production project-id
    var.env == "qa" ? "valkeyhubhost-500604" :                         # Replace with QA project-id
    var.env == "uat" ? "valkeyhubhost-500604" : "valkeyhubhost-500604" # Replace with UAT and dev project-ids
  )

  # Read & decode YAML manifest into a map.
  # var.manifest_file lets you point at whichever topology manifest you want
  # (memorystore-manifest-standalone.yaml / -ha.yaml / -dr.yaml) without
  # touching this file or main.tf.
  config = yamldecode(file("${path.module}/config/${var.manifest_file}"))

  # Access specific environment configuration based on env variable in TFC workspace
  target_env = lookup(local.config.dpe, var.env, {})

  # Flatten target_env and select only enabled ones
  enabled_configs = { for name, config in local.target_env : name => config if config.enabled }
}
