import { Namespace, Context } from "@ory/keto-namespace-types"

// Shared base namespaces used across all services.
class profile_user implements Namespace {}

class tenancy_access implements Namespace {
  related: {
    owner: (profile_user | SubjectSet<tenancy_access, "owner">)[]
    admin: (profile_user | SubjectSet<tenancy_access, "admin">)[]
    member: (profile_user | SubjectSet<tenancy_access, "member">)[]
    service: (profile_user | SubjectSet<tenancy_access, "service">)[]
  }
}

class service_audit implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]

    granted_audit_view: (profile_user | service_audit)[]
    granted_audit_create: (profile_user | service_audit)[]
    granted_audit_verify: (profile_user | service_audit)[]
  }

  permits = {
    audit_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_audit_view.includes(ctx.subject),

    audit_create: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_audit_create.includes(ctx.subject),

    audit_verify: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_audit_verify.includes(ctx.subject),
  }
}

class service_authentication implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]

    granted_auth_view_own: (profile_user | service_authentication)[]
    granted_auth_view_all: (profile_user | service_authentication)[]
  }

  permits = {
    auth_view_own: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_auth_view_own.includes(ctx.subject),

    auth_view_all: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_auth_view_all.includes(ctx.subject),
  }
}

class service_billing implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_catalog_view: (profile_user | service_billing)[]
    granted_catalog_manage: (profile_user | service_billing)[]
    granted_plan_manage: (profile_user | service_billing)[]
    granted_component_manage: (profile_user | service_billing)[]
    granted_tier_manage: (profile_user | service_billing)[]
    granted_subscription_view: (profile_user | service_billing)[]
    granted_subscription_manage: (profile_user | service_billing)[]
    granted_usage_view: (profile_user | service_billing)[]
    granted_usage_ingest: (profile_user | service_billing)[]
    granted_billing_run_view: (profile_user | service_billing)[]
    granted_billing_run_manage: (profile_user | service_billing)[]
    granted_invoice_view: (profile_user | service_billing)[]
    granted_invoice_manage: (profile_user | service_billing)[]
    granted_payment_record: (profile_user | service_billing)[]
    granted_payment_collect: (profile_user | service_billing)[]
    granted_credit_view: (profile_user | service_billing)[]
    granted_credit_manage: (profile_user | service_billing)[]
    granted_discount_view: (profile_user | service_billing)[]
    granted_discount_manage: (profile_user | service_billing)[]
  }

  permits = {
    catalog_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_catalog_view.includes(ctx.subject),

    catalog_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_catalog_manage.includes(ctx.subject),

    plan_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_plan_manage.includes(ctx.subject),

    component_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_component_manage.includes(ctx.subject),

    tier_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_tier_manage.includes(ctx.subject),

    subscription_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_subscription_view.includes(ctx.subject),

    subscription_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_subscription_manage.includes(ctx.subject),

    usage_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_usage_view.includes(ctx.subject),

    usage_ingest: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_usage_ingest.includes(ctx.subject),

    billing_run_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_billing_run_view.includes(ctx.subject),

    billing_run_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_billing_run_manage.includes(ctx.subject),

    invoice_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_invoice_view.includes(ctx.subject),

    invoice_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_invoice_manage.includes(ctx.subject),

    payment_record: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_payment_record.includes(ctx.subject),

    payment_collect: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_payment_collect.includes(ctx.subject),

    credit_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_credit_view.includes(ctx.subject),

    credit_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_credit_manage.includes(ctx.subject),

    discount_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_discount_view.includes(ctx.subject),

    discount_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_discount_manage.includes(ctx.subject),
  }
}

class service_checkout implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]

    granted_checkout_session_create: (profile_user | service_checkout)[]
    granted_checkout_session_view: (profile_user | service_checkout)[]
    granted_checkout_link_create: (profile_user | service_checkout)[]
  }

  permits = {
    checkout_session_create: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_checkout_session_create.includes(ctx.subject),

    checkout_session_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_checkout_session_view.includes(ctx.subject),

    checkout_link_create: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_checkout_link_create.includes(ctx.subject),
  }
}

class service_device implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_device_view: (profile_user | service_device)[]
    granted_device_manage: (profile_user | service_device)[]
    granted_device_key_view: (profile_user | service_device)[]
    granted_device_key_manage: (profile_user | service_device)[]
    granted_device_log_view: (profile_user | service_device)[]
    granted_device_log_manage: (profile_user | service_device)[]
  }

  permits = {
    device_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_device_view.includes(ctx.subject),

    device_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_device_manage.includes(ctx.subject),

    device_key_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_device_key_view.includes(ctx.subject),

    device_key_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_device_key_manage.includes(ctx.subject),

    device_log_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_device_log_view.includes(ctx.subject),

    device_log_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_device_log_manage.includes(ctx.subject),
  }
}

class service_field implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_agent_view: (profile_user | service_field)[]
    granted_agent_manage: (profile_user | service_field)[]
    granted_agent_subagent_manage: (profile_user | service_field)[]
    granted_client_view: (profile_user | service_field)[]
    granted_client_manage: (profile_user | service_field)[]
    granted_client_relationship_view: (profile_user | service_field)[]
    granted_client_relationship_manage: (profile_user | service_field)[]
  }

  permits = {
    agent_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_agent_view.includes(ctx.subject),

    agent_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_agent_manage.includes(ctx.subject),

    agent_subagent_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_agent_subagent_manage.includes(ctx.subject),

    client_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_client_view.includes(ctx.subject),

    client_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_client_manage.includes(ctx.subject),

    client_relationship_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_client_relationship_view.includes(ctx.subject),

    client_relationship_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_client_relationship_manage.includes(ctx.subject),
  }
}

class service_file implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_content_view: (profile_user | service_file)[]
    granted_content_upload: (profile_user | service_file)[]
    granted_content_manage: (profile_user | service_file)[]
    granted_content_delete: (profile_user | service_file)[]
    granted_file_access_view: (profile_user | service_file)[]
    granted_file_access_manage: (profile_user | service_file)[]
  }

  permits = {
    content_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_content_view.includes(ctx.subject),

    content_upload: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_content_upload.includes(ctx.subject),

    content_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_content_manage.includes(ctx.subject),

    content_delete: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_content_delete.includes(ctx.subject),

    file_access_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_file_access_view.includes(ctx.subject),

    file_access_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_file_access_manage.includes(ctx.subject),
  }
}

class service_funding implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_investor_account_view: (profile_user | service_funding)[]
    granted_investor_account_manage: (profile_user | service_funding)[]
    granted_fund_manage: (profile_user | service_funding)[]
  }

  permits = {
    investor_account_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_investor_account_view.includes(ctx.subject),

    investor_account_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_investor_account_manage.includes(ctx.subject),

    fund_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_fund_manage.includes(ctx.subject),
  }
}

class service_geolocation implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_location_ingest: (profile_user | service_geolocation)[]
    granted_area_view: (profile_user | service_geolocation)[]
    granted_area_manage: (profile_user | service_geolocation)[]
    granted_route_view: (profile_user | service_geolocation)[]
    granted_route_manage: (profile_user | service_geolocation)[]
    granted_track_view: (profile_user | service_geolocation)[]
    granted_nearby_view: (profile_user | service_geolocation)[]
  }

  permits = {
    location_ingest: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_location_ingest.includes(ctx.subject),

    area_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_area_view.includes(ctx.subject),

    area_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_area_manage.includes(ctx.subject),

    route_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_route_view.includes(ctx.subject),

    route_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_route_manage.includes(ctx.subject),

    track_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_track_view.includes(ctx.subject),

    nearby_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_nearby_view.includes(ctx.subject),
  }
}

class service_identity implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_organization_view: (profile_user | service_identity)[]
    granted_organization_manage: (profile_user | service_identity)[]
    granted_branch_view: (profile_user | service_identity)[]
    granted_branch_manage: (profile_user | service_identity)[]
    granted_workforce_member_view: (profile_user | service_identity)[]
    granted_workforce_member_manage: (profile_user | service_identity)[]
    granted_department_view: (profile_user | service_identity)[]
    granted_department_manage: (profile_user | service_identity)[]
    granted_position_view: (profile_user | service_identity)[]
    granted_position_manage: (profile_user | service_identity)[]
    granted_position_assignment_view: (profile_user | service_identity)[]
    granted_position_assignment_manage: (profile_user | service_identity)[]
    granted_team_view: (profile_user | service_identity)[]
    granted_team_manage: (profile_user | service_identity)[]
    granted_team_membership_view: (profile_user | service_identity)[]
    granted_team_membership_manage: (profile_user | service_identity)[]
    granted_access_role_assignment_view: (profile_user | service_identity)[]
    granted_access_role_assignment_manage: (profile_user | service_identity)[]
    granted_investor_view: (profile_user | service_identity)[]
    granted_investor_manage: (profile_user | service_identity)[]
    granted_system_user_view: (profile_user | service_identity)[]
    granted_system_user_manage: (profile_user | service_identity)[]
    granted_client_group_view: (profile_user | service_identity)[]
    granted_client_group_manage: (profile_user | service_identity)[]
    granted_membership_view: (profile_user | service_identity)[]
    granted_membership_manage: (profile_user | service_identity)[]
    granted_investor_account_view: (profile_user | service_identity)[]
    granted_investor_account_manage: (profile_user | service_identity)[]
    granted_client_data_view: (profile_user | service_identity)[]
    granted_client_data_manage: (profile_user | service_identity)[]
    granted_client_data_verify: (profile_user | service_identity)[]
    granted_form_template_view: (profile_user | service_identity)[]
    granted_form_template_manage: (profile_user | service_identity)[]
    granted_form_submission_view: (profile_user | service_identity)[]
    granted_form_submission_manage: (profile_user | service_identity)[]
  }

  permits = {
    organization_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_organization_view.includes(ctx.subject),
    organization_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_organization_manage.includes(ctx.subject),

    branch_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_branch_view.includes(ctx.subject),
    branch_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_branch_manage.includes(ctx.subject),

    workforce_member_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_workforce_member_view.includes(ctx.subject),
    workforce_member_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_workforce_member_manage.includes(ctx.subject),

    department_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_department_view.includes(ctx.subject),
    department_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_department_manage.includes(ctx.subject),

    position_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_position_view.includes(ctx.subject),
    position_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_position_manage.includes(ctx.subject),

    position_assignment_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_position_assignment_view.includes(ctx.subject),
    position_assignment_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_position_assignment_manage.includes(ctx.subject),

    team_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_team_view.includes(ctx.subject),
    team_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_team_manage.includes(ctx.subject),

    team_membership_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_team_membership_view.includes(ctx.subject),
    team_membership_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_team_membership_manage.includes(ctx.subject),

    access_role_assignment_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_access_role_assignment_view.includes(ctx.subject),
    access_role_assignment_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_access_role_assignment_manage.includes(ctx.subject),

    investor_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_investor_view.includes(ctx.subject),
    investor_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_investor_manage.includes(ctx.subject),

    system_user_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_system_user_view.includes(ctx.subject),
    system_user_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_system_user_manage.includes(ctx.subject),

    client_group_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_client_group_view.includes(ctx.subject),
    client_group_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_client_group_manage.includes(ctx.subject),

    membership_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_membership_view.includes(ctx.subject),
    membership_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_membership_manage.includes(ctx.subject),

    investor_account_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_investor_account_view.includes(ctx.subject),
    investor_account_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_investor_account_manage.includes(ctx.subject),

    client_data_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_client_data_view.includes(ctx.subject),
    client_data_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_client_data_manage.includes(ctx.subject),
    client_data_verify: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_client_data_verify.includes(ctx.subject),

    form_template_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_form_template_view.includes(ctx.subject),
    form_template_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_form_template_manage.includes(ctx.subject),

    form_submission_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_form_submission_view.includes(ctx.subject),
    form_submission_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_form_submission_manage.includes(ctx.subject),
  }
}

class service_ledger implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_ledger_view: (profile_user | service_ledger)[]
    granted_ledger_manage: (profile_user | service_ledger)[]
    granted_account_view: (profile_user | service_ledger)[]
    granted_account_manage: (profile_user | service_ledger)[]
    granted_transaction_view: (profile_user | service_ledger)[]
    granted_transaction_manage: (profile_user | service_ledger)[]
  }

  permits = {
    ledger_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_ledger_view.includes(ctx.subject),

    ledger_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_ledger_manage.includes(ctx.subject),

    account_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_account_view.includes(ctx.subject),

    account_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_account_manage.includes(ctx.subject),

    transaction_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_transaction_view.includes(ctx.subject),

    transaction_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_transaction_manage.includes(ctx.subject),
  }
}

class service_limits implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_limits_use: (profile_user | service_limits)[]
    granted_limits_policy_manage: (profile_user | service_limits)[]
    granted_limits_policy_view: (profile_user | service_limits)[]
    granted_limits_approval_view: (profile_user | service_limits)[]
    granted_limits_approval_act: (profile_user | service_limits)[]
    granted_limits_approval_override: (profile_user | service_limits)[]
    granted_limits_ledger_view: (profile_user | service_limits)[]
    granted_limits_audit_view: (profile_user | service_limits)[]
  }

  permits = {
    limits_use: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_limits_use.includes(ctx.subject),

    limits_policy_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_limits_policy_manage.includes(ctx.subject),

    limits_policy_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_limits_policy_view.includes(ctx.subject),

    limits_approval_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_limits_approval_view.includes(ctx.subject),

    limits_approval_act: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_limits_approval_act.includes(ctx.subject),

    limits_approval_override: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_limits_approval_override.includes(ctx.subject),

    limits_ledger_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_limits_ledger_view.includes(ctx.subject),

    limits_audit_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_limits_audit_view.includes(ctx.subject),
  }
}

class service_loans implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_loan_product_view: (profile_user | service_loans)[]
    granted_loan_product_manage: (profile_user | service_loans)[]
    granted_loan_request_view: (profile_user | service_loans)[]
    granted_loan_request_manage: (profile_user | service_loans)[]
    granted_loan_request_submit: (profile_user | service_loans)[]
    granted_client_product_access_view: (profile_user | service_loans)[]
    granted_client_product_access_manage: (profile_user | service_loans)[]
    granted_loan_view: (profile_user | service_loans)[]
    granted_loan_manage: (profile_user | service_loans)[]
    granted_disbursement_view: (profile_user | service_loans)[]
    granted_disbursement_manage: (profile_user | service_loans)[]
    granted_repayment_view: (profile_user | service_loans)[]
    granted_repayment_manage: (profile_user | service_loans)[]
    granted_penalty_view: (profile_user | service_loans)[]
    granted_penalty_manage: (profile_user | service_loans)[]
    granted_restructure_view: (profile_user | service_loans)[]
    granted_restructure_manage: (profile_user | service_loans)[]
    granted_reconciliation_manage: (profile_user | service_loans)[]
    granted_collection_manage: (profile_user | service_loans)[]
    granted_portfolio_view: (profile_user | service_loans)[]
    granted_portfolio_export: (profile_user | service_loans)[]
  }

  permits = {
    loan_product_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_loan_product_view.includes(ctx.subject),
    loan_product_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_loan_product_manage.includes(ctx.subject),

    loan_request_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_loan_request_view.includes(ctx.subject),
    loan_request_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_loan_request_manage.includes(ctx.subject),
    loan_request_submit: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_loan_request_submit.includes(ctx.subject),

    client_product_access_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_client_product_access_view.includes(ctx.subject),
    client_product_access_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_client_product_access_manage.includes(ctx.subject),

    loan_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_loan_view.includes(ctx.subject),
    loan_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_loan_manage.includes(ctx.subject),

    disbursement_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_disbursement_view.includes(ctx.subject),
    disbursement_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_disbursement_manage.includes(ctx.subject),

    repayment_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_repayment_view.includes(ctx.subject),
    repayment_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_repayment_manage.includes(ctx.subject),

    penalty_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_penalty_view.includes(ctx.subject),
    penalty_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_penalty_manage.includes(ctx.subject),

    restructure_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_restructure_view.includes(ctx.subject),
    restructure_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_restructure_manage.includes(ctx.subject),

    reconciliation_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_reconciliation_manage.includes(ctx.subject),

    collection_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_collection_manage.includes(ctx.subject),

    portfolio_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.member.includes(ctx.subject) || this.related.operator.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.viewer.includes(ctx.subject) || this.related.granted_portfolio_view.includes(ctx.subject),
    portfolio_export: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) || this.related.owner.includes(ctx.subject) || this.related.service.includes(ctx.subject) || this.related.granted_portfolio_export.includes(ctx.subject),
  }
}

class service_notification implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_notification_send: (profile_user | service_notification)[]
    granted_notification_release: (profile_user | service_notification)[]
    granted_notification_search: (profile_user | service_notification)[]
    granted_notification_status_view: (profile_user | service_notification)[]
    granted_notification_status_update: (profile_user | service_notification)[]
    granted_template_manage: (profile_user | service_notification)[]
    granted_template_view: (profile_user | service_notification)[]
  }

  permits = {
    notification_send: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_notification_send.includes(ctx.subject),

    notification_release: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_notification_release.includes(ctx.subject),

    notification_search: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_notification_search.includes(ctx.subject),

    notification_status_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_notification_status_view.includes(ctx.subject),

    notification_status_update: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_notification_status_update.includes(ctx.subject),

    template_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_template_manage.includes(ctx.subject),

    template_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_template_view.includes(ctx.subject),
  }
}

class service_operations implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_transfer_execute: (profile_user | service_operations)[]
    granted_transfer_view: (profile_user | service_operations)[]
    granted_payment_notify: (profile_user | service_operations)[]
    granted_payment_allocate: (profile_user | service_operations)[]
  }

  permits = {
    transfer_execute: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_transfer_execute.includes(ctx.subject),

    transfer_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_transfer_view.includes(ctx.subject),

    payment_notify: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_payment_notify.includes(ctx.subject),

    payment_allocate: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_payment_allocate.includes(ctx.subject),
  }
}

class service_payment implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_payment_send: (profile_user | service_payment)[]
    granted_payment_receive: (profile_user | service_payment)[]
    granted_payment_search: (profile_user | service_payment)[]
    granted_payment_status_view: (profile_user | service_payment)[]
    granted_payment_status_update: (profile_user | service_payment)[]
    granted_payment_release: (profile_user | service_payment)[]
    granted_prompt_initiate: (profile_user | service_payment)[]
    granted_payment_link_create: (profile_user | service_payment)[]
    granted_reconcile: (profile_user | service_payment)[]
  }

  permits = {
    payment_send: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_payment_send.includes(ctx.subject),

    payment_receive: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_payment_receive.includes(ctx.subject),

    payment_search: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_payment_search.includes(ctx.subject),

    payment_status_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_payment_status_view.includes(ctx.subject),

    payment_status_update: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_payment_status_update.includes(ctx.subject),

    payment_release: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_payment_release.includes(ctx.subject),

    prompt_initiate: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_prompt_initiate.includes(ctx.subject),

    payment_link_create: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_payment_link_create.includes(ctx.subject),

    reconcile: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_reconcile.includes(ctx.subject),
  }
}

class service_profile implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_profile_view: (profile_user | service_profile)[]
    granted_profile_create: (profile_user | service_profile)[]
    granted_profile_update: (profile_user | service_profile)[]
    granted_profile_merge: (profile_user | service_profile)[]
    granted_contact_manage: (profile_user | service_profile)[]
    granted_roster_view: (profile_user | service_profile)[]
    granted_roster_manage: (profile_user | service_profile)[]
    granted_address_manage: (profile_user | service_profile)[]
    granted_relationship_view: (profile_user | service_profile)[]
    granted_relationship_manage: (profile_user | service_profile)[]
  }

  permits = {
    profile_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_profile_view.includes(ctx.subject),

    profile_create: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_profile_create.includes(ctx.subject),

    profile_update: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_profile_update.includes(ctx.subject),

    profile_merge: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_profile_merge.includes(ctx.subject),

    contact_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_contact_manage.includes(ctx.subject),

    roster_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_roster_view.includes(ctx.subject),

    roster_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_roster_manage.includes(ctx.subject),

    address_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_address_manage.includes(ctx.subject),

    relationship_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_relationship_view.includes(ctx.subject),

    relationship_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_relationship_manage.includes(ctx.subject),
  }
}

class service_savings implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_savings_product_view: (profile_user | service_savings)[]
    granted_savings_product_manage: (profile_user | service_savings)[]
    granted_savings_account_view: (profile_user | service_savings)[]
    granted_savings_account_manage: (profile_user | service_savings)[]
    granted_deposit_view: (profile_user | service_savings)[]
    granted_deposit_manage: (profile_user | service_savings)[]
    granted_withdrawal_view: (profile_user | service_savings)[]
    granted_withdrawal_manage: (profile_user | service_savings)[]
    granted_interest_view: (profile_user | service_savings)[]
    granted_savings_balance_view: (profile_user | service_savings)[]
  }

  permits = {
    savings_product_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_savings_product_view.includes(ctx.subject),

    savings_product_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_savings_product_manage.includes(ctx.subject),

    savings_account_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_savings_account_view.includes(ctx.subject),

    savings_account_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_savings_account_manage.includes(ctx.subject),

    deposit_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_deposit_view.includes(ctx.subject),

    deposit_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_deposit_manage.includes(ctx.subject),

    withdrawal_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_withdrawal_view.includes(ctx.subject),

    withdrawal_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_withdrawal_manage.includes(ctx.subject),

    interest_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_interest_view.includes(ctx.subject),

    savings_balance_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_savings_balance_view.includes(ctx.subject),
  }
}

class service_setting implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_setting_view: (profile_user | service_setting)[]
    granted_setting_manage: (profile_user | service_setting)[]
  }

  permits = {
    setting_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_setting_view.includes(ctx.subject),

    setting_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_setting_manage.includes(ctx.subject),
  }
}

class service_tenancy implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]

    granted_tenant_view: (profile_user | service_tenancy)[]
    granted_tenant_manage: (profile_user | service_tenancy)[]
    granted_partition_view: (profile_user | service_tenancy)[]
    granted_partition_manage: (profile_user | service_tenancy)[]
    granted_access_view: (profile_user | service_tenancy)[]
    granted_access_manage: (profile_user | service_tenancy)[]
    granted_role_manage: (profile_user | service_tenancy)[]
    granted_page_view: (profile_user | service_tenancy)[]
    granted_page_manage: (profile_user | service_tenancy)[]
    granted_permission_grant: (profile_user | service_tenancy)[]
    granted_service_account_view: (profile_user | service_tenancy)[]
    granted_service_account_manage: (profile_user | service_tenancy)[]
    granted_client_view: (profile_user | service_tenancy)[]
    granted_client_manage: (profile_user | service_tenancy)[]
  }

  permits = {
    tenant_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_tenant_view.includes(ctx.subject),

    tenant_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_tenant_manage.includes(ctx.subject),

    partition_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_partition_view.includes(ctx.subject),

    partition_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_partition_manage.includes(ctx.subject),

    access_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_access_view.includes(ctx.subject),

    access_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_access_manage.includes(ctx.subject),

    role_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_role_manage.includes(ctx.subject),

    page_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_page_view.includes(ctx.subject),

    page_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_page_manage.includes(ctx.subject),

    permission_grant: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_permission_grant.includes(ctx.subject),

    service_account_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_service_account_view.includes(ctx.subject),

    service_account_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_service_account_manage.includes(ctx.subject),

    client_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_client_view.includes(ctx.subject),

    client_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_client_manage.includes(ctx.subject),
  }
}

class service_trustage implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_event_ingest: (profile_user | service_trustage)[]
    granted_workflow_view: (profile_user | service_trustage)[]
    granted_workflow_manage: (profile_user | service_trustage)[]
    granted_instance_view: (profile_user | service_trustage)[]
    granted_instance_retry: (profile_user | service_trustage)[]
    granted_execution_view: (profile_user | service_trustage)[]
    granted_execution_retry: (profile_user | service_trustage)[]
    granted_execution_resume: (profile_user | service_trustage)[]
    granted_signal_send: (profile_user | service_trustage)[]
  }

  permits = {
    event_ingest: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_event_ingest.includes(ctx.subject),

    workflow_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_workflow_view.includes(ctx.subject),

    workflow_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_workflow_manage.includes(ctx.subject),

    instance_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_instance_view.includes(ctx.subject),

    instance_retry: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_instance_retry.includes(ctx.subject),

    execution_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_execution_view.includes(ctx.subject),

    execution_retry: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_execution_retry.includes(ctx.subject),

    execution_resume: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_execution_resume.includes(ctx.subject),

    signal_send: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_signal_send.includes(ctx.subject),
  }
}

class file implements Namespace {
  related: {
    granted_owner: profile_user[]
    granted_viewer: profile_user[]
    granted_editor: profile_user[]
    granted_uploader: profile_user[]
  }

  permits = {
    view: (ctx: Context): boolean =>
      this.related.granted_owner.includes(ctx.subject) ||
      this.related.granted_viewer.includes(ctx.subject),

    edit: (ctx: Context): boolean =>
      this.related.granted_owner.includes(ctx.subject) ||
      this.related.granted_editor.includes(ctx.subject),

    delete: (ctx: Context): boolean =>
      this.related.granted_owner.includes(ctx.subject),

    upload: (ctx: Context): boolean =>
      this.related.granted_owner.includes(ctx.subject) ||
      this.related.granted_uploader.includes(ctx.subject),

    stats: (ctx: Context): boolean =>
      this.related.granted_owner.includes(ctx.subject),

    share: (ctx: Context): boolean =>
      this.related.granted_owner.includes(ctx.subject),

    retention_set: (ctx: Context): boolean =>
      this.related.granted_owner.includes(ctx.subject),

    lock: (ctx: Context): boolean =>
      this.related.granted_owner.includes(ctx.subject),
  }
}

// file_version namespace represents historical versions of files.
// Inherits permissions from the parent file.

class file_version implements Namespace {
  related: {
    parent: file[]
    creator: profile_user[]
  }

  permits = {
    view: (ctx: Context): boolean =>
      this.related.parent.traverse((f) => f.permits.view(ctx)),

    delete: (ctx: Context): boolean =>
      this.related.parent.traverse((f) => f.permits.delete(ctx)),

    restore: (ctx: Context): boolean =>
      this.related.parent.traverse((f) => f.permits.edit(ctx)),
  }
}

// file_retention_policy namespace represents retention policies
// that can be applied to files.

class file_retention_policy implements Namespace {
  related: {
    granted_owner: profile_user[]
    files: file[]
  }

  permits = {
    view: (ctx: Context): boolean =>
      this.related.granted_owner.includes(ctx.subject),

    update: (ctx: Context): boolean =>
      this.related.granted_owner.includes(ctx.subject),

    delete: (ctx: Context): boolean =>
      this.related.granted_owner.includes(ctx.subject),

    apply: (ctx: Context): boolean =>
      this.related.granted_owner.includes(ctx.subject),
  }
}

// file_thumbnail namespace represents thumbnails generated from files.
// Permissions inherit from the parent file.

class file_thumbnail implements Namespace {
  related: {
    parent: file[]
  }

  permits = {
    view: (ctx: Context): boolean =>
      this.related.parent.traverse((f) => f.permits.view(ctx)),

    regenerate: (ctx: Context): boolean =>
      this.related.parent.traverse((f) => f.permits.edit(ctx)),
  }
}

// file_upload namespace represents multipart upload sessions.
// Tracks in-progress uploads.

class file_upload implements Namespace {
  related: {
    granted_uploader: profile_user[]
    target_file: file[]
  }

  permits = {
    write: (ctx: Context): boolean =>
      this.related.granted_uploader.includes(ctx.subject),

    complete: (ctx: Context): boolean =>
      this.related.granted_uploader.includes(ctx.subject),

    cancel: (ctx: Context): boolean =>
      this.related.granted_uploader.includes(ctx.subject),

    status: (ctx: Context): boolean =>
      this.related.granted_uploader.includes(ctx.subject),
  }
}

class service_ocr implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_ocr_submit: (profile_user | service_ocr)[]
    granted_ocr_status_view: (profile_user | service_ocr)[]
  }

  permits = {
    ocr_submit: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_ocr_submit.includes(ctx.subject),

    ocr_status_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_ocr_status_view.includes(ctx.subject),
  }
}

class commerce_shop implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: profile_user[]

    granted_shop_view: profile_user[]
    granted_shop_update: profile_user[]
    granted_products_view: profile_user[]
    granted_products_manage: profile_user[]
    granted_orders_view: profile_user[]
    granted_orders_manage: profile_user[]
    granted_fulfilment_view: profile_user[]
    granted_fulfilment_manage: profile_user[]
    granted_price_list_view: profile_user[]
    granted_price_list_manage: profile_user[]
    granted_customer_price_override: profile_user[]
    granted_discount_manage: profile_user[]
    granted_discount_approve: profile_user[]
  }

  permits = {
    // --- View permits: any role on the shop (incl. viewer/member) ---
    shop_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_shop_view.includes(ctx.subject),

    products_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_products_view.includes(ctx.subject),

    orders_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_orders_view.includes(ctx.subject),

    fulfilment_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_fulfilment_view.includes(ctx.subject),

    price_list_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_price_list_view.includes(ctx.subject),

    // --- Manage permits: owner/admin/operator (operational roles) ---
    shop_update: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_shop_update.includes(ctx.subject),

    products_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_products_manage.includes(ctx.subject),

    orders_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_orders_manage.includes(ctx.subject),

    fulfilment_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_fulfilment_manage.includes(ctx.subject),

    price_list_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_price_list_manage.includes(ctx.subject),

    // --- Sensitive permits: owner/admin only ---
    customer_price_override: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_customer_price_override.includes(ctx.subject),

    discount_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_discount_manage.includes(ctx.subject),

    discount_approve: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_discount_approve.includes(ctx.subject),
  }
}

class service_commerce implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_shop_view: (profile_user | service_commerce)[]
    granted_shop_create: (profile_user | service_commerce)[]
    granted_shop_update: (profile_user | service_commerce)[]
    granted_product_view: (profile_user | service_commerce)[]
    granted_product_manage: (profile_user | service_commerce)[]
    granted_cart_view: (profile_user | service_commerce)[]
    granted_cart_manage: (profile_user | service_commerce)[]
    granted_order_view: (profile_user | service_commerce)[]
    granted_order_manage: (profile_user | service_commerce)[]
    granted_fulfilment_view: (profile_user | service_commerce)[]
    granted_fulfilment_manage: (profile_user | service_commerce)[]
  }

  permits = {
    shop_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_shop_view.includes(ctx.subject),

    shop_create: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_shop_create.includes(ctx.subject),

    shop_update: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_shop_update.includes(ctx.subject),

    product_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_product_view.includes(ctx.subject),

    product_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_product_manage.includes(ctx.subject),

    cart_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_cart_view.includes(ctx.subject),

    cart_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_cart_manage.includes(ctx.subject),

    order_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_order_view.includes(ctx.subject),

    order_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_order_manage.includes(ctx.subject),

    fulfilment_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_fulfilment_view.includes(ctx.subject),

    fulfilment_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_fulfilment_manage.includes(ctx.subject),
  }
}

class procurement_property implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: profile_user[]

    granted_property_view: profile_user[]
    granted_property_update: profile_user[]
    granted_purchase_order_manage: profile_user[]
    granted_purchase_order_property_view: profile_user[]
    granted_goods_receipt_manage: profile_user[]
    granted_goods_receipt_view: profile_user[]
  }

  permits = {
    // --- View permits: any role on the property ---
    property_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_property_view.includes(ctx.subject),

    purchase_order_property_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_purchase_order_property_view.includes(ctx.subject),

    goods_receipt_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_goods_receipt_view.includes(ctx.subject),

    // --- Manage permits: owner/admin/operator ---
    property_update: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_property_update.includes(ctx.subject),

    purchase_order_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_purchase_order_manage.includes(ctx.subject),

    goods_receipt_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_goods_receipt_manage.includes(ctx.subject),
  }
}

class service_procurement implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_supplier_view: (profile_user | service_procurement)[]
    granted_supplier_manage: (profile_user | service_procurement)[]
    granted_purchase_order_view: (profile_user | service_procurement)[]
    granted_purchase_order_create: (profile_user | service_procurement)[]
    granted_purchase_order_submit: (profile_user | service_procurement)[]
    granted_purchase_order_cancel: (profile_user | service_procurement)[]
    granted_goods_receipt_view: (profile_user | service_procurement)[]
    granted_goods_receipt_create: (profile_user | service_procurement)[]
  }

  permits = {
    supplier_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_supplier_view.includes(ctx.subject),

    supplier_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_supplier_manage.includes(ctx.subject),

    purchase_order_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_purchase_order_view.includes(ctx.subject),

    purchase_order_create: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_purchase_order_create.includes(ctx.subject),

    purchase_order_submit: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_purchase_order_submit.includes(ctx.subject),

    purchase_order_cancel: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_purchase_order_cancel.includes(ctx.subject),

    goods_receipt_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_goods_receipt_view.includes(ctx.subject),

    goods_receipt_create: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_goods_receipt_create.includes(ctx.subject),
  }
}

class service_property implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_property_type_view: (profile_user | service_property)[]
    granted_property_type_manage: (profile_user | service_property)[]
    granted_locality_manage: (profile_user | service_property)[]
    granted_property_view: (profile_user | service_property)[]
    granted_property_manage: (profile_user | service_property)[]
    granted_property_subscription_view: (profile_user | service_property)[]
    granted_property_subscription_manage: (profile_user | service_property)[]
  }

  permits = {
    property_type_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_property_type_view.includes(ctx.subject),

    property_type_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_property_type_manage.includes(ctx.subject),

    locality_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_locality_manage.includes(ctx.subject),

    property_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_property_view.includes(ctx.subject),

    property_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_property_manage.includes(ctx.subject),

    property_subscription_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_property_subscription_view.includes(ctx.subject),

    property_subscription_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_property_subscription_manage.includes(ctx.subject),
  }
}

class service_chat_agent implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_chat_agent_view: (profile_user | service_chat_agent)[]
    granted_chat_agent_manage: (profile_user | service_chat_agent)[]
    granted_chat_agent_turn: (profile_user | service_chat_agent)[]
  }

  permits = {
    chat_agent_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_chat_agent_view.includes(ctx.subject),

    chat_agent_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_chat_agent_manage.includes(ctx.subject),

    chat_agent_turn: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_chat_agent_turn.includes(ctx.subject),
  }
}

class service_calendar implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_calendar_resource_view: (profile_user | service_calendar)[]
    granted_calendar_resource_manage: (profile_user | service_calendar)[]
    granted_calendar_availability_manage: (profile_user | service_calendar)[]
    granted_calendar_slot_view: (profile_user | service_calendar)[]
    granted_calendar_booking_view: (profile_user | service_calendar)[]
    granted_calendar_booking_manage: (profile_user | service_calendar)[]
    granted_calendar_sync_manage: (profile_user | service_calendar)[]
  }

  permits = {
    calendar_resource_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_calendar_resource_view.includes(ctx.subject),

    calendar_resource_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_calendar_resource_manage.includes(ctx.subject),

    calendar_availability_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_calendar_availability_manage.includes(ctx.subject),

    calendar_slot_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_calendar_slot_view.includes(ctx.subject),

    calendar_booking_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_calendar_booking_view.includes(ctx.subject),

    calendar_booking_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_calendar_booking_manage.includes(ctx.subject),

    calendar_sync_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_calendar_sync_manage.includes(ctx.subject),
  }
}

class service_ats implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_ats_dashboard_view: (profile_user | service_ats)[]
    granted_ats_job_view: (profile_user | service_ats)[]
    granted_ats_job_manage: (profile_user | service_ats)[]
    granted_ats_application_view: (profile_user | service_ats)[]
    granted_ats_application_manage: (profile_user | service_ats)[]
    granted_ats_interview_view: (profile_user | service_ats)[]
    granted_ats_interview_manage: (profile_user | service_ats)[]
    granted_ats_talent_view: (profile_user | service_ats)[]
    granted_ats_talent_manage: (profile_user | service_ats)[]
    granted_ats_availability_manage: (profile_user | service_ats)[]
    granted_ats_ai_use: (profile_user | service_ats)[]
    granted_ats_hire: (profile_user | service_ats)[]
    granted_ats_publish: (profile_user | service_ats)[]
  }

  permits = {
    ats_dashboard_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_ats_dashboard_view.includes(ctx.subject),

    ats_job_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_ats_job_view.includes(ctx.subject),

    ats_job_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_ats_job_manage.includes(ctx.subject),

    ats_application_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_ats_application_view.includes(ctx.subject),

    ats_application_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_ats_application_manage.includes(ctx.subject),

    ats_interview_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_ats_interview_view.includes(ctx.subject),

    ats_interview_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_ats_interview_manage.includes(ctx.subject),

    ats_talent_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_ats_talent_view.includes(ctx.subject),

    ats_talent_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_ats_talent_manage.includes(ctx.subject),

    ats_availability_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_ats_availability_manage.includes(ctx.subject),

    ats_ai_use: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_ats_ai_use.includes(ctx.subject),

    ats_hire: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_ats_hire.includes(ctx.subject),

    ats_publish: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_ats_publish.includes(ctx.subject),
  }
}

class service_imports implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_vehicles_view: (profile_user | service_imports)[]
    granted_vehicles_create: (profile_user | service_imports)[]
    granted_vehicles_update: (profile_user | service_imports)[]
    granted_vehicles_delete: (profile_user | service_imports)[]
    granted_requests_view: (profile_user | service_imports)[]
    granted_requests_update: (profile_user | service_imports)[]
    granted_quotes_view: (profile_user | service_imports)[]
    granted_quotes_create: (profile_user | service_imports)[]
    granted_quotes_update: (profile_user | service_imports)[]
    granted_orders_view: (profile_user | service_imports)[]
    granted_orders_update: (profile_user | service_imports)[]
    granted_payments_view: (profile_user | service_imports)[]
    granted_payments_create: (profile_user | service_imports)[]
    granted_payments_update: (profile_user | service_imports)[]
    granted_analytics_view: (profile_user | service_imports)[]
    granted_transactions_view: (profile_user | service_imports)[]
    granted_transactions_update: (profile_user | service_imports)[]
    granted_acquisition_authorize: (profile_user | service_imports)[]
  }

  permits = {
    vehicles_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_vehicles_view.includes(ctx.subject),

    vehicles_create: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_vehicles_create.includes(ctx.subject),

    vehicles_update: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_vehicles_update.includes(ctx.subject),

    vehicles_delete: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_vehicles_delete.includes(ctx.subject),

    requests_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_requests_view.includes(ctx.subject),

    requests_update: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_requests_update.includes(ctx.subject),

    quotes_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_quotes_view.includes(ctx.subject),

    quotes_create: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_quotes_create.includes(ctx.subject),

    quotes_update: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_quotes_update.includes(ctx.subject),

    orders_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_orders_view.includes(ctx.subject),

    orders_update: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_orders_update.includes(ctx.subject),

    payments_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_payments_view.includes(ctx.subject),

    payments_create: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_payments_create.includes(ctx.subject),

    payments_update: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_payments_update.includes(ctx.subject),

    analytics_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_analytics_view.includes(ctx.subject),

    transactions_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_transactions_view.includes(ctx.subject),

    transactions_update: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_transactions_update.includes(ctx.subject),

    acquisition_authorize: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_acquisition_authorize.includes(ctx.subject),
  }
}

class manufacturing_property implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: profile_user[]

    granted_recipe_view: profile_user[]
    granted_recipe_manage: profile_user[]
    granted_plan_view: profile_user[]
    granted_plan_manage: profile_user[]
    granted_plan_validate: profile_user[]
    granted_batch_view: profile_user[]
    granted_batch_operate: profile_user[]
    granted_batch_complete: profile_user[]
    granted_batch_override: profile_user[]
    granted_inventory_view: profile_user[]
    granted_inventory_manage: profile_user[]
    granted_inventory_adjust: profile_user[]
    granted_equipment_view: profile_user[]
    granted_equipment_manage: profile_user[]
    granted_cold_chain_view: profile_user[]
    granted_cold_chain_manage: profile_user[]
    granted_shelf_life_view: profile_user[]
    granted_shelf_life_manage: profile_user[]
    granted_inspection_view: profile_user[]
    granted_inspection_perform: profile_user[]
    granted_inspection_override: profile_user[]
    granted_inspection_template_manage: profile_user[]
    granted_waste_view: profile_user[]
    granted_waste_record: profile_user[]
    granted_waste_dispose: profile_user[]
    granted_costing_view: profile_user[]
    granted_costing_manage: profile_user[]
    granted_trace_view: profile_user[]
    granted_recall_initiate: profile_user[]
    granted_recall_manage: profile_user[]
    granted_recall_resolve: profile_user[]
    granted_demand_view: profile_user[]
    granted_demand_manage: profile_user[]
  }

  permits = {
    // --- View permits: any role on the property ---
    recipe_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_recipe_view.includes(ctx.subject),

    plan_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_plan_view.includes(ctx.subject),

    batch_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_batch_view.includes(ctx.subject),

    inventory_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_inventory_view.includes(ctx.subject),

    equipment_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_equipment_view.includes(ctx.subject),

    cold_chain_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_cold_chain_view.includes(ctx.subject),

    shelf_life_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_shelf_life_view.includes(ctx.subject),

    inspection_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_inspection_view.includes(ctx.subject),

    waste_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_waste_view.includes(ctx.subject),

    costing_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_costing_view.includes(ctx.subject),

    trace_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_trace_view.includes(ctx.subject),

    demand_view: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_demand_view.includes(ctx.subject),

    // --- Operate / manage permits: owner/admin/operator ---
    recipe_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_recipe_manage.includes(ctx.subject),

    plan_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_plan_manage.includes(ctx.subject),

    plan_validate: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_plan_validate.includes(ctx.subject),

    batch_operate: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_batch_operate.includes(ctx.subject),

    batch_complete: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_batch_complete.includes(ctx.subject),

    inventory_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_inventory_manage.includes(ctx.subject),

    inventory_adjust: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_inventory_adjust.includes(ctx.subject),

    equipment_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_equipment_manage.includes(ctx.subject),

    cold_chain_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_cold_chain_manage.includes(ctx.subject),

    shelf_life_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_shelf_life_manage.includes(ctx.subject),

    inspection_perform: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_inspection_perform.includes(ctx.subject),

    inspection_template_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_inspection_template_manage.includes(ctx.subject),

    waste_record: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_waste_record.includes(ctx.subject),

    waste_dispose: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_waste_dispose.includes(ctx.subject),

    costing_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_costing_manage.includes(ctx.subject),

    recall_initiate: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_recall_initiate.includes(ctx.subject),

    recall_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_recall_manage.includes(ctx.subject),

    demand_manage: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_demand_manage.includes(ctx.subject),

    // --- Override / resolve permits: owner/admin only ---
    batch_override: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_batch_override.includes(ctx.subject),

    inspection_override: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_inspection_override.includes(ctx.subject),

    recall_resolve: (ctx: Context): boolean =>
      this.related.owner.includes(ctx.subject) ||
      this.related.admin.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_recall_resolve.includes(ctx.subject),
  }
}

class service_manufacturing implements Namespace {
  related: {
    owner: profile_user[]
    admin: profile_user[]
    operator: profile_user[]
    viewer: profile_user[]
    member: profile_user[]
    service: (profile_user | tenancy_access)[]

    granted_recipe_view: (profile_user | service_manufacturing)[]
    granted_recipe_manage: (profile_user | service_manufacturing)[]
    granted_plan_view: (profile_user | service_manufacturing)[]
    granted_plan_manage: (profile_user | service_manufacturing)[]
    granted_plan_validate: (profile_user | service_manufacturing)[]
    granted_batch_view: (profile_user | service_manufacturing)[]
    granted_batch_operate: (profile_user | service_manufacturing)[]
    granted_batch_complete: (profile_user | service_manufacturing)[]
    granted_batch_override: (profile_user | service_manufacturing)[]
    granted_inventory_view: (profile_user | service_manufacturing)[]
    granted_inventory_manage: (profile_user | service_manufacturing)[]
    granted_inventory_adjust: (profile_user | service_manufacturing)[]
    granted_equipment_view: (profile_user | service_manufacturing)[]
    granted_equipment_manage: (profile_user | service_manufacturing)[]
    granted_cleaning_perform: (profile_user | service_manufacturing)[]
    granted_cleaning_verify: (profile_user | service_manufacturing)[]
    granted_maintenance_manage: (profile_user | service_manufacturing)[]
    granted_environment_view: (profile_user | service_manufacturing)[]
    granted_environment_record: (profile_user | service_manufacturing)[]
    granted_environment_alarm_acknowledge: (profile_user | service_manufacturing)[]
    granted_environment_manage: (profile_user | service_manufacturing)[]
    granted_shelf_life_view: (profile_user | service_manufacturing)[]
    granted_shelf_life_manage: (profile_user | service_manufacturing)[]
    granted_label_view: (profile_user | service_manufacturing)[]
    granted_inspection_view: (profile_user | service_manufacturing)[]
    granted_inspection_perform: (profile_user | service_manufacturing)[]
    granted_inspection_override: (profile_user | service_manufacturing)[]
    granted_inspection_template_manage: (profile_user | service_manufacturing)[]
    granted_waste_view: (profile_user | service_manufacturing)[]
    granted_waste_record: (profile_user | service_manufacturing)[]
    granted_waste_dispose: (profile_user | service_manufacturing)[]
    granted_costing_view: (profile_user | service_manufacturing)[]
    granted_costing_manage: (profile_user | service_manufacturing)[]
    granted_trace_view: (profile_user | service_manufacturing)[]
    granted_recall_initiate: (profile_user | service_manufacturing)[]
    granted_recall_manage: (profile_user | service_manufacturing)[]
    granted_recall_resolve: (profile_user | service_manufacturing)[]
    granted_demand_view: (profile_user | service_manufacturing)[]
    granted_demand_manage: (profile_user | service_manufacturing)[]
  }

  permits = {
    recipe_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_recipe_view.includes(ctx.subject),

    recipe_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_recipe_manage.includes(ctx.subject),

    plan_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_plan_view.includes(ctx.subject),

    plan_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_plan_manage.includes(ctx.subject),

    plan_validate: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_plan_validate.includes(ctx.subject),

    batch_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_batch_view.includes(ctx.subject),

    batch_operate: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_batch_operate.includes(ctx.subject),

    batch_complete: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_batch_complete.includes(ctx.subject),

    batch_override: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_batch_override.includes(ctx.subject),

    inventory_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_inventory_view.includes(ctx.subject),

    inventory_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_inventory_manage.includes(ctx.subject),

    inventory_adjust: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_inventory_adjust.includes(ctx.subject),

    equipment_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_equipment_view.includes(ctx.subject),

    equipment_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_equipment_manage.includes(ctx.subject),

    cleaning_perform: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_cleaning_perform.includes(ctx.subject),

    cleaning_verify: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_cleaning_verify.includes(ctx.subject),

    maintenance_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_maintenance_manage.includes(ctx.subject),

    environment_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_environment_view.includes(ctx.subject),

    environment_record: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_environment_record.includes(ctx.subject),

    environment_alarm_acknowledge: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_environment_alarm_acknowledge.includes(ctx.subject),

    environment_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_environment_manage.includes(ctx.subject),

    shelf_life_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_shelf_life_view.includes(ctx.subject),

    shelf_life_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_shelf_life_manage.includes(ctx.subject),

    label_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_label_view.includes(ctx.subject),

    inspection_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_inspection_view.includes(ctx.subject),

    inspection_perform: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_inspection_perform.includes(ctx.subject),

    inspection_override: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_inspection_override.includes(ctx.subject),

    inspection_template_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_inspection_template_manage.includes(ctx.subject),

    waste_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_waste_view.includes(ctx.subject),

    waste_record: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_waste_record.includes(ctx.subject),

    waste_dispose: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_waste_dispose.includes(ctx.subject),

    costing_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_costing_view.includes(ctx.subject),

    costing_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_costing_manage.includes(ctx.subject),

    trace_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_trace_view.includes(ctx.subject),

    recall_initiate: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_recall_initiate.includes(ctx.subject),

    recall_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_recall_manage.includes(ctx.subject),

    recall_resolve: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_recall_resolve.includes(ctx.subject),

    demand_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_demand_view.includes(ctx.subject),

    demand_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_demand_manage.includes(ctx.subject),
  }
}
