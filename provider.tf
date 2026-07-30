terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.39.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

provider "google" {
  project = local._env_infra.project_id
}
