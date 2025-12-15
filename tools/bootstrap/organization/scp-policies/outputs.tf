output "organization_id" {
  description = "The ID of the AWS Organization"
  value       = data.aws_organizations_organization.current.id
}

output "enabled_policies" {
  description = "List of enabled policy names"
  value = compact([
    var.enable_instance_type_restrictions ? "RestrictEC2InstanceTypes" : "",
    var.require_imdsv2 ? "RequireIMDSv2" : "",
    var.require_ebs_encryption ? "RequireEBSEncryption" : "",
    var.protect_s3_buckets ? "DenyS3BucketDeletion" : "",
    var.require_s3_versioning ? "RequireS3Versioning" : "",
    var.require_rds_encryption ? "RequireRDSEncryption" : "",
    var.deny_rds_public_access ? "DenyRDSPublicAccess" : "",
    var.protect_vpc_resources ? "ProtectVPCResources" : "",
    var.deny_internet_gateway ? "DenyInternetGateway" : "",
    var.require_vpc_flow_logs ? "RequireVPCFlowLogs" : "",
    var.protect_security_hub ? "ProtectSecurityHub" : "",
    var.protect_guardduty ? "ProtectGuardDuty" : "",
    var.enforce_sso_only ? "DenyIAMUserCreation" : "",
    var.restrict_expensive_resources ? "DenyExpensiveInstances" : "",
    var.protect_reserved_instances ? "ProtectReservedInstances" : ""
  ])
}

output "policy_ids" {
  description = "Map of policy names to policy IDs"
  value       = local.policy_map
}

output "policy_arns" {
  description = "Map of policy names to policy ARNs"
  value = merge(
    var.enable_instance_type_restrictions ? { "RestrictEC2InstanceTypes" = aws_organizations_policy.restrict_instance_types[0].arn } : {},
    var.require_imdsv2 ? { "RequireIMDSv2" = aws_organizations_policy.require_imdsv2[0].arn } : {},
    var.require_ebs_encryption ? { "RequireEBSEncryption" = aws_organizations_policy.require_ebs_encryption[0].arn } : {},
    var.protect_s3_buckets ? { "DenyS3BucketDeletion" = aws_organizations_policy.deny_s3_deletion[0].arn } : {},
    var.require_s3_versioning ? { "RequireS3Versioning" = aws_organizations_policy.require_s3_versioning[0].arn } : {},
    var.require_rds_encryption ? { "RequireRDSEncryption" = aws_organizations_policy.require_rds_encryption[0].arn } : {},
    var.deny_rds_public_access ? { "DenyRDSPublicAccess" = aws_organizations_policy.deny_rds_public_access[0].arn } : {},
    var.protect_vpc_resources ? { "ProtectVPCResources" = aws_organizations_policy.protect_vpc[0].arn } : {},
    var.deny_internet_gateway ? { "DenyInternetGateway" = aws_organizations_policy.deny_internet_gateway[0].arn } : {},
    var.require_vpc_flow_logs ? { "RequireVPCFlowLogs" = aws_organizations_policy.require_vpc_flow_logs[0].arn } : {},
    var.protect_security_hub ? { "ProtectSecurityHub" = aws_organizations_policy.protect_security_hub[0].arn } : {},
    var.protect_guardduty ? { "ProtectGuardDuty" = aws_organizations_policy.protect_guardduty[0].arn } : {},
    var.enforce_sso_only ? { "DenyIAMUserCreation" = aws_organizations_policy.deny_iam_users[0].arn } : {},
    var.restrict_expensive_resources ? { "DenyExpensiveInstances" = aws_organizations_policy.deny_expensive_instances[0].arn } : {},
    var.protect_reserved_instances ? { "ProtectReservedInstances" = aws_organizations_policy.protect_reserved_instances[0].arn } : {}
  )
}

output "attached_policies" {
  description = "List of policy attachments"
  value = [
    for k, v in var.policy_attachments : {
      name      = v.policy_name
      target_id = v.target_ou_id
      policy_id = lookup(local.policy_map, v.policy_name, "not-found")
    }
  ]
}

output "policy_summary" {
  description = "Summary of SCP configuration"
  value = {
    total_policies_available = length(local.policy_map)
    enabled_policies         = length(compact([
      var.enable_instance_type_restrictions ? "1" : "",
      var.require_imdsv2 ? "1" : "",
      var.require_ebs_encryption ? "1" : "",
      var.protect_s3_buckets ? "1" : "",
      var.require_s3_versioning ? "1" : "",
      var.require_rds_encryption ? "1" : "",
      var.deny_rds_public_access ? "1" : "",
      var.protect_vpc_resources ? "1" : "",
      var.deny_internet_gateway ? "1" : "",
      var.require_vpc_flow_logs ? "1" : "",
      var.protect_security_hub ? "1" : "",
      var.protect_guardduty ? "1" : "",
      var.enforce_sso_only ? "1" : "",
      var.restrict_expensive_resources ? "1" : "",
      var.protect_reserved_instances ? "1" : ""
    ]))
    attached_policies = length(var.policy_attachments)
  }
}
