run "deploy" {
  variables {
    env              = "test"
    location         = "malaysiawest"
    sql_location     = "eastasia"
    cosmos_location  = "malaysiawest"
    address_space    = "10.43.0.0/16"
    image_repository = "ghcr.io/ryet7/malus-be"
    auth_audience    = "api://malus-api"
  }
}

run "gateway_healthz" {
  module {
    source = "./tests/modules/http_check"
  }

  variables {
    url = "${run.deploy.gateway_url}/healthz"
  }

  assert {
    condition     = output.status_code == 200
    error_message = "Gateway /healthz did not return 200 after deployment."
  }
}

run "questions_through_gateway" {
  module {
    source = "./tests/modules/http_check"
  }

  variables {
    url = "${run.deploy.gateway_url}/v1/questions"
  }

  assert {
    condition     = output.status_code == 200
    error_message = "GET /v1/questions did not return 200: gateway, interaction service or Cosmos DB access is broken."
  }
}
