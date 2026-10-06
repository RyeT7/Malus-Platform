# Malus-Platform

Terraform for the Malus presentation app on Azure for Students. The subscription only allows `centralindia`, `malaysiawest`, `koreacentral`, `indiasouthcentral` and `eastasia`; everything here runs in `eastasia`, which also hosts Static Web Apps.

## Layout

| Path | Applied | What it owns |
|---|---|---|
| `bootstrap/` | Once, from a laptop, local state | Remote-state storage account, GitHub OIDC identity and federated credentials, subscription policies (tag inheritance, deny public SQL), optional budget |
| `stacks/core/` | CI, one state per env | Everything the app needs: VNet, Container Apps, Azure SQL, Cosmos DB, Blob Storage, Key Vault, Service Bus, Web PubSub, Static Web App, App Insights |
| `modules/container_app/` | via core | One Go service on Container Apps: user-assigned identity, `/healthz` and `/readyz` probes, scale to zero |
| `modules/aks_showcase/` | via core, `showcase_enabled = true` | One-node AKS with workload identity, KEDA, Cilium network policy |

## What core deploys

| Service | Container App | Ingress | Data and identity |
|---|---|---|---|
| gateway | `ca-malus-<env>-gateway` | **external** (only public entry) | Entra JWKS; forwards to the others over `http://ca-malus-<env>-<svc>` |
| content | `ca-malus-<env>-content` | internal | Azure SQL (Entra-only, private endpoint), blobs, Service Bus sender |
| interaction | `ca-malus-<env>-interaction` | internal | Cosmos DB `malus/questions` (`/pk`), data-plane RBAC, keys disabled |
| realtime | `ca-malus-<env>-realtime` | internal | Web PubSub Service Owner |
| worker | `ca-malus-<env>-worker` | none | Service Bus receiver, blobs |

Each service gets its own user-assigned identity, exposed as `AZURE_CLIENT_ID` so `DefaultAzureCredential` picks it up. No connection strings or keys are created.

`caj-malus-<env>-migrate` is a Container Apps job that runs `/app migrate` with the content image inside the VNet, because the SQL server is not reachable from outside.

## Cost shape

| Item | Idle cost |
|---|---|
| Container Apps (consumption, min 0) | ~$0 inside the monthly free grant |
| Azure SQL serverless with the free offer, auto-pause | $0 within 100k vCore-seconds/month |
| SQL private endpoint | ~$7/month per env while it exists |
| Cosmos DB free tier (prod) / serverless (dev) | $0 / cents |
| Service Bus Basic, Web PubSub Free, Static Web Apps Free, Key Vault | ~$0 |
| Log Analytics + App Insights | capped at `log_daily_quota_gb` (0.15 GB/day) |
| AKS showcase | ~$1.5–2/day, only while `showcase_enabled = true` |

Dev only exists after you run `deploy-dev.yaml`, and is destroyed every night by `nightly.yaml`, so only prod's private endpoint is paid for all month. Each day dev is up costs about $0.26, mostly its private endpoint.

## First-time setup

1. Bootstrap (needs Owner on the subscription). It also registers the Azure resource providers the stack uses; a fresh Azure for Students subscription has none registered, and registration can take a few minutes on the first run:

   Bootstrap keeps its own state as `bootstrap.tfstate` in the storage account it creates, so the very first run uses a temporary local backend and then migrates:

   ```sh
   cd bootstrap
   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
   export TF_VAR_budget_contact_emails='["<you>@example.com"]'
   printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf
   terraform init
   terraform apply -var-file=env/shared.tfvars
   rm backend_override.tf
   terraform init -migrate-state -backend-config=env/shared.backend.hcl
   rm terraform.tfstate terraform.tfstate.backup
   ```

   The budget line is optional; leave it out to skip the budget. Answer "yes" when `-migrate-state` asks to copy the local state. After that, every bootstrap run is `terraform init -backend-config=env/shared.backend.hcl` followed by `terraform plan`/`apply -var-file=env/shared.tfvars`. `bootstrap/env/shared.tfvars` is committed with the region and GitHub owner; the budget email is passed as an environment variable so it stays out of the repo.

   The state storage account carries a `CanNotDelete` lock, and `id-malus-github` a `ReadOnly` lock. To tear bootstrap down, remove both locks and migrate the state back to local first (re-add `backend_override.tf`, then `terraform init -migrate-state`).

2. The state storage account name is derived from the subscription ID, so `stacks/core/env/*.backend.hcl` already contains it (`stmalustfd01f08`). Check it matches the `state_storage_account` output.
3. Make the five `ghcr.io/ryet7/malus-be-<service>` packages public on GitHub. Images are pulled from `<image_repository>-<service>:<tag>` (for example `ghcr.io/ryet7/malus-be-gateway:sha-<commit>`), which is what the Malus-BE `publish-image` job pushes; it must have run on `main` at least once before the first core apply.
4. Set `auth_audience` in `stacks/core/env/*.tfvars` to the API's app ID URI or client ID from Entra. The school tenant does not allow creating app registrations, so this needs a tenant where you can register an app (see `auth_tenant_id`).
5. In each of the three GitHub repos, add the repository secrets (Settings → Secrets and variables → Actions → Secrets) `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` from the bootstrap output, so they are masked in workflow logs, and create the environments `dev` and `prod`. Put required reviewers on `prod` only; reviewers on `dev` would block the nightly destroy.

### Changing the GitHub trust rules

`id-malus-github` carries a `ReadOnly` lock, because its Contributor role would otherwise let a compromised workflow add a federated credential for another repository and keep access. Only an Owner can remove the lock. To add a repository or environment:

```sh
az lock delete -n malus-github-identity-readonly -g rg-malus-shared --resource id-malus-github --resource-type Microsoft.ManagedIdentity/userAssignedIdentities
cd bootstrap
terraform init -backend-config=env/shared.backend.hcl
terraform apply -var-file=env/shared.tfvars
```

The apply recreates the lock. Logins are unaffected by the lock; it only blocks changes.

## Day to day

```sh
cd stacks/core
terraform init -backend-config=env/dev.backend.hcl
terraform plan -var-file=env/dev.tfvars
terraform test -filter=tests/core.tftest.hcl
```

Always pass `-filter`. A bare `terraform test` also runs `tests/deploy.tftest.hcl`, which deploys a real `test` environment to Azure. In PowerShell the filter path uses a backslash: `terraform test '-filter=tests\core.tftest.hcl'`.

- New images: CI runs `az containerapp update --image ...`; Terraform ignores image and traffic-weight drift so the two don't fight. After a content rollout, run the migration job.

## Pipelines

| Workflow | Runs on | Jobs |
|---|---|---|
| `ci.yaml` | Pull requests | `check` (fmt, validate, mocked tests) → `plan-dev` and `prod-safety`; `deploy-test` when `stacks/`, `modules/`, `.github/actions/` or `ci.yaml` changed |
| `deploy.yaml` | Push to `main`, manual | `check` → `prod` (approval, apply + smoke test) |
| `deploy-dev.yaml` | Manual only | `dev` (apply + smoke test): a sandbox for the frontend, new backend images and debugging, gone after the nightly destroy |
| `nightly.yaml` | 16:00 UTC daily, manual | `destroy-dev`; `cleanup-test` deletes a leftover `rg-malus-test` |
| `k8s.yaml` | Changes under `deploy/` | Helm lint, kubeconform, kind end-to-end test |

Repeated steps live in composite actions under `.github/actions/`: `terraform-init`, `terraform-check`, `terraform-plan`, `terraform-apply` (apply + smoke test), `smoke-test` and `remove-test-env`. Composite actions can't read secrets, so the workflows pass the Azure IDs in as inputs.

- **`deploy-test`** runs `tests/deploy.tftest.hcl`: a real apply of a throwaway `test` environment (`rg-malus-test`, `10.43.0.0/16`), then `/healthz` and `/v1/questions` through the gateway must return 200, then everything is destroyed. It takes about 20–30 minutes and a few cents. Only one runs at a time, and leftovers from an interrupted run are deleted before the next one starts.
- **`prod-safety`** plans against prod's real state (read-only, no lock) and fails if the change would delete or replace a stateful resource: the SQL server or database, the Cosmos DB account, database or container, the storage account or its containers, or Key Vault. A fresh deploy succeeding doesn't prove that updating prod is safe; renaming the SQL server, for example, would recreate it and lose its data.
- **Smoke tests** after every apply (`deploy.yaml`, `deploy-dev.yaml`) call `/healthz` and `/v1/questions`, retrying while the apps cold-start.
- **Dev is not in the merge path.** The pull request's `deploy-test` already proves a change deploys from scratch, so merges go straight to prod's approval. Two PRs that pass separately but break together would only be caught by prod's smoke test.
- **`cleanup-test`** shares the `deploy-test` concurrency group, so it waits for a running deployment test instead of deleting it.

## Presentation week

In `env/prod.tfvars`:

```hcl
webpubsub_sku        = "Standard_S1"
gateway_min_replicas = 1
showcase_enabled     = true
```

Apply, rehearse, present, then revert those three lines and apply again.

## Kubernetes

`deploy/charts/malus` is one Helm chart for all five services. Each service gets a Deployment, a ServiceAccount named after the service (matching the federated credentials Terraform creates), a Service (except the worker), optional HPA, and a NetworkPolicy. The namespace denies all traffic by default; only the gateway accepts traffic from anywhere, and content, interaction and realtime accept it only from the gateway. Pods run as the distroless `nonroot` user with a read-only root filesystem. Database migrations run as a Helm post-install/post-upgrade Job.

| Target | Values | Notes |
|---|---|---|
| kind (local and CI) | `deploy/kind/values.yaml` | `APP_ENV=local`, auth disabled; SQL Server and the Cosmos DB emulator in `malus-deps`, mirroring Malus-BE's `compose.yaml` |
| AKS showcase | generated by Terraform | Workload identity, LoadBalancer gateway, optional KEDA Service Bus scaler for the worker |

Local cluster (needs Docker, kind, kubectl, helm):

```sh
cd ../Malus-BE && docker compose build && cd ../Malus-Platform
kind create cluster --config deploy/kind/kind-config.yaml
for s in gateway content interaction realtime worker; do kind load docker-image malus-be/$s:local --name malus; done
kubectl apply -f deploy/kind/dependencies.yaml
kubectl -n malus-deps wait --for=condition=complete job/sqlserver-init --timeout=5m
helm upgrade --install malus deploy/charts/malus -n malus --create-namespace -f deploy/kind/values.yaml --wait
curl http://localhost:8080/v1/sections
```

AKS showcase (after applying prod with `showcase_enabled = true`):

```sh
cd stacks/core
terraform output -raw aks_helm_values > aks.values.yaml
az aks get-credentials -g rg-malus-prod -n aks-malus-prod
helm upgrade --install malus ../../deploy/charts/malus -n malus --create-namespace -f aks.values.yaml --set global.image.tag=<sha> --wait
```

`aks.values.yaml` contains the App Insights connection string, so don't commit it.

The `k8s` workflow lints the chart, validates the rendered manifests with kubeconform, then builds the Malus-BE images, installs everything on kind and calls `/healthz`, `/v1/sections` (SQL) and `/v1/questions` (Cosmos DB emulator) through the gateway. If Malus-BE is private, add a read-only token as the `MALUS_BE_READ_TOKEN` secret.

## Known gaps

- The content identity is also the SQL Entra admin, so the migration job can create tables without a manual `CREATE USER` step. Splitting runtime and migration identities needs a one-time T-SQL grant from inside the VNet.
- Worker scaling stays at 0–1 replicas until it reads Service Bus; the KEDA `azure-servicebus` rule should be added then.
- Not built yet: second region and Front Door for the failover drill, Flux/Argo CD on AKS, Infracost and Conftest in PR checks, drift detection.
- The services don't read `BLOB_ENDPOINT`, `SERVICEBUS_NAMESPACE`, `WEBPUBSUB_ENDPOINT`/`WEBPUBSUB_HUB`, `KEY_VAULT_URI` or `APPLICATIONINSIGHTS_CONNECTION_STRING` yet; they are set now so the code can adopt them without an infra change.
