# cloudrun-api-gateway

Path-based Global HTTPS load balancer for a single hostname (typically
`api.stawi.org`) with Cloud Run backends in **multiple GCP projects**.

## GCP layout

| Resource | Project |
|----------|---------|
| Global IP, URL map, HTTPS proxy, Certificate Manager, Cloudflare DNS | `project_id` (gateway) |
| Serverless NEG + backend service | each route’s `backend_project` |
| Cloud Run service | same as `backend_project` |

Global external Application Load Balancer supports cross-project backend
service references without Shared VPC. Grant
`roles/compute.loadBalancerServiceUser` on backend projects to the gateway
project’s `gcp-sa-backendservices` agent.

## Path rewrite

When `strip_prefix = true` (default), a request to
`https://api.stawi.org/profile/v1/…` is rewritten to `/v1/…` before Cloud Run.
This matches the K8s Gateway `ReplacePrefixMatch: /` convention used by Frame
Connect/REST services.

## Usage

```hcl
module "gateway" {
  source     = "../../modules/cloudrun-api-gateway"
  project_id = "stawi-api"
  name       = "api-gw"
  hostname   = "api.stawi.org"
  routes = {
    profile = {
      path_prefix     = "/profile"
      service         = "identity-profile"
      backend_project = "stawi-identity"
      region          = "europe-west1"
    }
  }
  cloudflare_zone_id = var.cloudflare_zone_id
}
```

App root: [`apps/api-gateway`](../../apps/api-gateway).
