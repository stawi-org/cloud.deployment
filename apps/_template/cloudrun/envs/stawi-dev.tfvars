app_name = "REPLACE_ME"
image    = "us-docker.pkg.dev/cloudrun/container/hello"
platform = "stawi-dev"
# neon_api_key from TF_VAR_neon_api_key / -var in CI
# app_name is overridden by CI: -var=app_name=${{ inputs.app }}
