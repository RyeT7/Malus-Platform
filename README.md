# Malus-Platform

Terraform for the Malus presentation app on Azure for Students. The subscription only allows `centralindia`, `malaysiawest`, `koreacentral`, `indiasouthcentral` and `eastasia`; everything here runs in `eastasia`, which also hosts Static Web Apps.

## Layout

| Path | Applied | What it owns |
|---|---|---|
| `bootstrap/` | Once, from a laptop; state in `bootstrap.tfstate` | Remote-state storage account, GitHub OIDC identity and federated credentials, subscription policies (tag inheritance, deny public SQL), optional budget |
| `identity/` | From a laptop, signed in to the `Malus` tenant; state in `identity.tfstate` | The Entra app registration for admin sign-in: API scope, `admin` app role, SPA redirect URIs, admin assignments |
| `stacks/core/` | CI, one state per env | Everything the app needs: VNet, Container Apps, Azure SQL, Cosmos DB, Blob Storage, Key Vault, Service Bus, Web PubSub, Static Web App, App Insights |
| `modules/container_app/` | via core | One Go service on Container Apps: user-assigned identity, `/healthz` and `/readyz` probes, scale to zero |

## Admin sign-in (`identity/`)

The school tenant blocks app registrations, so sign-in uses a separate Entra tenant, `Malus` (`malusauth.onmicrosoft.com`, tenant ID `46a669c5-4e3e-4a49-9f12-efab7c00120d`), created by hand in the portal. Azure resources stay in the school subscription; only tokens come from `Malus`.

`identity/` manages one single-tenant app registration in it:

- API scope `api://<client_id>/access_as_user`, issuing v2 access tokens, so `iss` is `https://login.microsoftonline.com/<Malus tenant>/v2.0` and `aud` is the client ID, which is what the gateway checks.
- App role `admin` (the gateway's `AUTH_ADMIN_ROLE`), assigned to whoever applies the stack and to every address in `admin_emails`. Those are invited as guests and keep signing in with their own account.
- SPA redirect URIs `<origin>/redirect.html` for each entry in `spa_origins`.
- Tenant-wide consent for the API scope and for `openid`, `profile`, `offline_access`, so nobody gets a consent prompt.

GitHub Actions can't manage the `Malus` tenant (the CI identity lives in the school tenant), so this stack is applied from a laptop. State stays in the school storage account; the backend file pins the school tenant, the provider pins `Malus`:

```powershell
az login
az login --tenant 46a669c5-4e3e-4a49-9f12-efab7c00120d --allow-no-subscriptions
cd identity
$env:ARM_SUBSCRIPTION_ID = az account show --query id -o tsv
$env:TF_VAR_admin_emails = '["<other admin account>"]'
terraform init "-backend-config=env/identity.backend.hcl"
terraform apply "-var-file=env/identity.tfvars"
```

`TF_VAR_admin_emails` is optional and keeps addresses out of the repo. Order of operations on a fresh setup:

1. Apply `identity/` with only `http://localhost:5173` in `spa_origins`.
2. Copy `client_id` and `tenant_id` into `stacks/core/env/prod.tfvars` (`auth_audience`, `auth_tenant_id`) and deploy prod.
3. Add prod's `frontend_url` output to `spa_origins` and apply `identity/` again.
4. Build Malus-FE with `VITE_ENTRA_CLIENT_ID`, `VITE_ENTRA_TENANT_ID` and `VITE_ENTRA_API_SCOPE` from the outputs.

The deployment test gets no redirect URI: its Static Web App is created with a new random hostname on every run.

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
| Cosmos DB free tier (prod) / serverless (test) | $0 / cents |
| Service Bus Basic, Web PubSub Free, Static Web Apps Free, Key Vault | ~$0 |
| Log Analytics + App Insights | capped at `log_daily_quota_gb` (0.15 GB/day) |

The deployment test's resources exist only while a test runs (about $0.01 per run), so only prod's private endpoint is paid for all month.

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
4. Apply `identity/` (see "Admin sign-in" below), then set `auth_tenant_id` and `auth_audience` in `stacks/core/env/*.tfvars` from its `tenant_id` and `client_id` outputs.
5. In each of the three GitHub repos, add the repository secrets (Settings → Secrets and variables → Actions → Secrets) `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` from the bootstrap output, so they are masked in workflow logs, and create the environments `test` and `prod`. Put required reviewers on `prod` only; reviewers on `test` would block every pull request's deployment test and the nightly cleanup.

### Changing the GitHub trust rules

`id-malus-github` carries a `ReadOnly` lock, because its Contributor role would otherwise let a compromised workflow add a federated credential for another repository and keep access. Only an Owner can remove the lock. The repositories were created after 15 July 2026, so GitHub's OIDC subjects use the immutable format `repo:OWNER@OWNER-ID/REPO@REPO-ID:...`; the owner ID and each repository ID are in `bootstrap/env/shared.tfvars` (an ID is on the repository page, or in the subject quoted by a failed `AADSTS700213` login). To add a repository or environment:

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
terraform init -backend-config=env/prod.backend.hcl
terraform plan -lock=false -var-file=env/prod.tfvars
terraform test -filter=tests/core.tftest.hcl
```

Always pass `-filter`. A bare `terraform test` also runs `tests/deploy.tftest.hcl`, which deploys a real `test` environment to Azure. In PowerShell the filter path uses a backslash: `terraform test '-filter=tests\core.tftest.hcl'`.

- New images: CI runs `az containerapp update --image ...`; Terraform ignores image and traffic-weight drift so the two don't fight. Every prod apply runs the content migration job before the smoke test, so a fresh environment gets its tables; Malus-BE's deploy runs it again for each new content image.

## Pipelines

| Workflow | Runs on | Jobs |
|---|---|---|
| `ci.yaml` | Pull requests | `check` (fmt, validate, mocked tests) → `prod-safety` (prod plan in the PR summary, blocks destructive changes); `deploy-test` when `stacks/`, `modules/`, `.github/actions/` or `ci.yaml` changed |
| `deploy.yaml` | Push to `main`, manual | `check` → `prod` (approval, apply + smoke test) |
| `nightly.yaml` | 16:00 UTC daily, manual | `cleanup-test` deletes a leftover `rg-malus-test` |

Repeated steps live in composite actions under `.github/actions/`: `terraform-init`, `terraform-check`, `terraform-plan`, `terraform-apply` (apply, migration job, smoke test), `smoke-test` and `remove-test-env`. Composite actions can't read secrets, so the workflows pass the Azure IDs in as inputs.

- **`deploy-test`** runs `tests/deploy.tftest.hcl`: a real apply of a throwaway `test` environment (`rg-malus-test`, `10.43.0.0/16`), then `/healthz`, `/v1/questions` and `/v1/live/connection` through the gateway must return 200, then everything is destroyed. `/v1/presentation` isn't checked there because the test environment's database is never migrated. It takes about 20–30 minutes and a few cents. Only one runs at a time, and leftovers from an interrupted run are deleted before the next one starts.
- **`prod-safety`** plans against prod's real state (read-only, no lock) and fails if the change would delete or replace a stateful resource: the SQL server or database, the Cosmos DB account, database or container, the storage account or its containers, or Key Vault. A fresh deploy succeeding doesn't prove that updating prod is safe; renaming the SQL server, for example, would recreate it and lose its data.
- **Smoke tests** after every prod apply (`deploy.yaml`) call `/healthz`, `/v1/presentation` (content and SQL), `/v1/questions` (interaction and Cosmos DB) and `/v1/live/connection` (realtime, Cosmos DB and Web PubSub), retrying while the apps cold-start.
- **Dev is not in the merge path.** The pull request's `deploy-test` already proves a change deploys from scratch, so merges go straight to prod's approval. Two PRs that pass separately but break together would only be caught by prod's smoke test.
- **`cleanup-test`** shares the `deploy-test` concurrency group, so it waits for a running deployment test instead of deleting it.

## Presentation week

In `env/prod.tfvars`:

```hcl
webpubsub_sku        = "Standard_S1"
gateway_min_replicas = 1
```

Apply, rehearse, present, then revert those lines and apply again.

## Known gaps

- The subscription allows **one Container Apps environment in total** (`MaxNumberOfGlobalEnvironmentsInSubExceeded`), and prod has it. The deployment test therefore sets `shared_platform_env = "prod"`: it creates its own apps, identities, databases, Cosmos DB, storage, Key Vault, Service Bus, Web PubSub and Static Web App in its own resource group, but runs the apps in prod's Container Apps environment and uses prod's network, private DNS zone and Log Analytics workspace instead of creating its own. Deleting `rg-malus-test` removes only test resources.
- azurerm 5.8.0 fails while waiting for Container Apps and Container Apps jobs to delete, although Azure deletes them ([hashicorp/terraform-provider-azurerm#33433](https://github.com/hashicorp/terraform-provider-azurerm/issues/33433), fixed in 5.9.0, not released yet). Until then, `ci.yaml`'s `deploy-test` passes when every test run passed and only the teardown failed, then deletes `rg-malus-test` and fails if that fails; `nightly.yaml` runs `terraform destroy` a second time if the first fails. Once 5.9.0 is out, raise the azurerm constraint to `~> 5.9`, run `terraform init -upgrade`, and remove both workarounds.
- Cosmos DB runs in **Malaysia West** (`cosmos_location`), not East Asia: this subscription has no Cosmos DB access in East Asia (`isSubscriptionRegionAccessAllowedForRegular = false`). Malaysia West is the closest allowed region to the apps (35 ms median round trip from East Asia, per Azure's latency table). It is residency-restricted, so backups use `Local` redundancy. Moving the account later recreates it and loses its data, which `prod-safety` blocks; request East Asia access at https://aka.ms/cosmosdbquota first if you ever want to.
- The content identity is also the SQL Entra admin, so the migration job can create tables without a manual `CREATE USER` step. Splitting runtime and migration identities needs a one-time T-SQL grant from inside the VNet.
- Worker scaling stays at 0–1 replicas until it reads Service Bus; the KEDA `azure-servicebus` rule should be added then.
- Not built yet: second region and Front Door for the failover drill, Infracost and Conftest in PR checks, drift detection. The AKS showcase and the Helm chart were removed; the empty `snet-aks` subnet is kept for now because prod's NSG rule and Cosmos DB network rule still reference it, and removing it changes live network settings.
- The services don't read the worker's `BLOB_ENDPOINT`, `SERVICEBUS_NAMESPACE`, `KEY_VAULT_URI` or `APPLICATIONINSIGHTS_CONNECTION_STRING` yet; they are set now so the code can adopt them without an infra change. Content reads `BLOB_ACCOUNT_URL`, and realtime reads `WEBPUBSUB_ENDPOINT`/`WEBPUBSUB_HUB` and `COSMOS_ENDPOINT`/`COSMOS_DATABASE`/`COSMOS_SESSIONS_CONTAINER`; a setting name that doesn't match what the code reads makes that service fail at startup.
