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
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.granted_device_manage.includes(ctx.subject),

    device_key_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.service.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_device_key_view.includes(ctx.subject),

    device_key_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
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
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_agent_view.includes(ctx.subject),

    agent_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_agent_manage.includes(ctx.subject),

    agent_subagent_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_agent_subagent_manage.includes(ctx.subject),

    client_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_client_view.includes(ctx.subject),

    client_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_client_manage.includes(ctx.subject),

    client_relationship_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_client_relationship_view.includes(ctx.subject),

    client_relationship_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
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
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_investor_account_view.includes(ctx.subject),

    investor_account_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_investor_account_manage.includes(ctx.subject),

    fund_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
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
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_organization_view.includes(ctx.subject),

    organization_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_organization_manage.includes(ctx.subject),

    branch_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_branch_view.includes(ctx.subject),

    branch_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_branch_manage.includes(ctx.subject),

    workforce_member_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_workforce_member_view.includes(ctx.subject),

    workforce_member_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_workforce_member_manage.includes(ctx.subject),

    department_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_department_view.includes(ctx.subject),

    department_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_department_manage.includes(ctx.subject),

    position_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_position_view.includes(ctx.subject),

    position_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_position_manage.includes(ctx.subject),

    position_assignment_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_position_assignment_view.includes(ctx.subject),

    position_assignment_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_position_assignment_manage.includes(ctx.subject),

    team_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_team_view.includes(ctx.subject),

    team_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_team_manage.includes(ctx.subject),

    team_membership_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_team_membership_view.includes(ctx.subject),

    team_membership_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_team_membership_manage.includes(ctx.subject),

    access_role_assignment_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_access_role_assignment_view.includes(ctx.subject),

    access_role_assignment_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_access_role_assignment_manage.includes(ctx.subject),

    investor_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_investor_view.includes(ctx.subject),

    investor_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_investor_manage.includes(ctx.subject),

    client_group_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_client_group_view.includes(ctx.subject),

    client_group_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_client_group_manage.includes(ctx.subject),

    membership_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_membership_view.includes(ctx.subject),

    membership_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_membership_manage.includes(ctx.subject),

    investor_account_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_investor_account_view.includes(ctx.subject),

    investor_account_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_investor_account_manage.includes(ctx.subject),

    client_data_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_client_data_view.includes(ctx.subject),

    client_data_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_client_data_manage.includes(ctx.subject),

    client_data_verify: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_client_data_verify.includes(ctx.subject),

    form_template_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_form_template_view.includes(ctx.subject),

    form_template_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_form_template_manage.includes(ctx.subject),

    form_submission_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_form_submission_view.includes(ctx.subject),

    form_submission_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_form_submission_manage.includes(ctx.subject),
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
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_loan_product_view.includes(ctx.subject),

    loan_product_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_loan_product_manage.includes(ctx.subject),

    loan_request_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_loan_request_view.includes(ctx.subject),

    loan_request_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_loan_request_manage.includes(ctx.subject),

    loan_request_submit: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_loan_request_submit.includes(ctx.subject),

    client_product_access_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_client_product_access_view.includes(ctx.subject),

    client_product_access_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_client_product_access_manage.includes(ctx.subject),

    loan_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_loan_view.includes(ctx.subject),

    loan_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_loan_manage.includes(ctx.subject),

    disbursement_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_disbursement_view.includes(ctx.subject),

    disbursement_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_disbursement_manage.includes(ctx.subject),

    repayment_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_repayment_view.includes(ctx.subject),

    repayment_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_repayment_manage.includes(ctx.subject),

    penalty_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_penalty_view.includes(ctx.subject),

    penalty_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_penalty_manage.includes(ctx.subject),

    restructure_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_restructure_view.includes(ctx.subject),

    restructure_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_restructure_manage.includes(ctx.subject),

    reconciliation_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_reconciliation_manage.includes(ctx.subject),

    collection_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_collection_manage.includes(ctx.subject),

    portfolio_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_portfolio_view.includes(ctx.subject),

    portfolio_export: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_portfolio_export.includes(ctx.subject),
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
      this.related.granted_transfer_execute.includes(ctx.subject),

    transfer_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_transfer_view.includes(ctx.subject),

    payment_notify: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_payment_notify.includes(ctx.subject),

    payment_allocate: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
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
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_savings_product_view.includes(ctx.subject),

    savings_product_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_savings_product_manage.includes(ctx.subject),

    savings_account_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_savings_account_view.includes(ctx.subject),

    savings_account_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_savings_account_manage.includes(ctx.subject),

    deposit_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_deposit_view.includes(ctx.subject),

    deposit_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_deposit_manage.includes(ctx.subject),

    withdrawal_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_withdrawal_view.includes(ctx.subject),

    withdrawal_manage: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.granted_withdrawal_manage.includes(ctx.subject),

    interest_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
      this.related.viewer.includes(ctx.subject) ||
      this.related.granted_interest_view.includes(ctx.subject),

    savings_balance_view: (ctx: Context): boolean =>
      this.related.admin.includes(ctx.subject) ||
      this.related.member.includes(ctx.subject) ||
      this.related.operator.includes(ctx.subject) ||
      this.related.owner.includes(ctx.subject) ||
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
