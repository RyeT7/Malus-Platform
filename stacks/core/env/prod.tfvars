env              = "prod"
location         = "eastasia"
cosmos_location  = "malaysiawest"
address_space    = "10.42.0.0/16"
image_repository = "ghcr.io/ryet7/malus-be"
auth_tenant_id   = "46a669c5-4e3e-4a49-9f12-efab7c00120d"
auth_audience    = "aa4a4fa4-20c2-4301-9105-e131df1fc7a7"
cosmos_free_tier = true

gateway_min_replicas = 2
service_min_replicas = 2
