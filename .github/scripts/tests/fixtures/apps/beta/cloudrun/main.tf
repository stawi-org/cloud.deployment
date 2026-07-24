module "cloudrun" {
  source = "../../../modules/cloudrun-service"
}

module "neon" {
  source = "../../../modules/neon-database"
}
