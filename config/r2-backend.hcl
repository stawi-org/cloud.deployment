# config/r2-backend.hcl
# Used via: tofu init -backend-config=../../../config/r2-backend.hcl \
#                     -backend-config="key=cloud-deployment/apps/<app>/<env>/terraform.tfstate"
bucket                      = "cluster-tofu-state"
region                      = "auto"
use_path_style              = true
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_region_validation      = true
skip_requesting_account_id  = true
skip_s3_checksum            = true
use_lockfile                = true
encrypt                     = true
# endpoints.s3 supplied at init:
#   -backend-config="endpoints={s3=\"https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com\"}"
