# One-time state moves into module.frame (data.google_project stays app-local for multi-topic URLs).

moved {
  from = data.google_cloud_run_v2_service.hydra
  to   = module.frame.data.google_cloud_run_v2_service.hydra
}

moved {
  from = data.google_cloud_run_v2_service.keto_read
  to   = module.frame.data.google_cloud_run_v2_service.keto_read[0]
}

moved {
  from = data.google_cloud_run_v2_service.keto_write
  to   = module.frame.data.google_cloud_run_v2_service.keto_write[0]
}

moved {
  from = google_service_account.runtime
  to   = module.frame.google_service_account.runtime
}

moved {
  from = module.edge
  to   = module.frame.module.edge
}

moved {
  from = module.db[0]
  to   = module.frame.module.db[0]
}

moved {
  from = module.secrets
  to   = module.frame.module.secrets
}

moved {
  from = module.messaging
  to   = module.frame.module.messaging[0]
}

moved {
  from = module.migrate[0]
  to   = module.frame.module.migrate[0]
}

moved {
  from = module.service
  to   = module.frame.module.service
}

moved {
  from = google_secret_manager_secret_iam_member.hydra_webhook_psk
  to   = module.frame.google_secret_manager_secret_iam_member.oauth_signer[0]
}

moved {
  from = google_service_account_iam_member.pubsub_push_token_creator
  to   = module.frame.google_service_account_iam_member.pubsub_push_token_creator[0]
}

moved {
  from = google_cloud_run_v2_service_iam_member.pubsub_push_invoker
  to   = module.frame.google_cloud_run_v2_service_iam_member.pubsub_push_invoker[0]
}
