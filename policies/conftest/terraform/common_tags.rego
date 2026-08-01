# FILE_NAME: common_tags.rego
# DESCRIPTION: Require Environment + ManagedBy on tagged resources across all modules.
# VERSION: 0.2.0
# AUTHORS: gh-platform

package terraform.tags

import rego.v1
import data.terraform.util as util

required := {"Environment", "ManagedBy"}

# Resource types emitted by gh-platform-modules that accept tags.
tagged_types := {
	"aws_acm_certificate",
	"aws_cloudfront_distribution",
	"aws_cloudwatch_log_group",
	"aws_cognito_user_pool",
	"aws_db_instance",
	"aws_db_option_group",
	"aws_db_parameter_group",
	"aws_db_subnet_group",
	"aws_ec2_client_vpn_endpoint",
	"aws_ecr_repository",
	"aws_ecs_cluster",
	"aws_ecs_service",
	"aws_eip",
	"aws_instance",
	"aws_lb",
	"aws_lb_target_group",
	"aws_lambda_function",
	"aws_nat_gateway",
	"aws_s3_bucket",
	"aws_secretsmanager_secret",
	"aws_security_group",
	"aws_sfn_state_machine",
	"aws_sns_topic",
	"aws_subnet",
	"aws_vpc",
	"aws_vpc_endpoint",
	"aws_vpc_peering_connection",
	"aws_iam_role",
	"aws_scheduler_schedule",
	"aws_guardduty_detector",
	"aws_organizations_account",
	"aws_ssoadmin_permission_set",
	"aws_route53_zone",
	"aws_sesv2_configuration_set",
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type in tagged_types
	util.is_create_or_update(rc)
	tags := util.tags_of(rc)
	some key in required
	not tags[key]
	msg := sprintf("%s (%s) missing required tag %q (need Environment, ManagedBy)", [rc.address, rc.type, key])
}
