terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.39.0"
    }
  }
}

provider "google" {
  # Configuration options
  project = "my-project-id"
  region  = "us-east1"
}
