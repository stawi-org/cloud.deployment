# Minimal TFLint config for local/CI optional use.
# Modules and app roots target OpenTofu; enable rules gradually.

config {
  call_module_type = "local"
  force            = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
