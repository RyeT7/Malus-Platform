terraform {
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.6"
    }
  }
}

variable "url" {
  type = string
}

data "http" "check" {
  url = var.url

  retry {
    attempts     = 40
    min_delay_ms = 5000
    max_delay_ms = 15000
  }
}

output "status_code" {
  value = data.http.check.status_code
}
