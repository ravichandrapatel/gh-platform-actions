# FILE_NAME: required_tags.rego
# DESCRIPTION: Require Environment and ManagedBy tags on tagged AWS resources in the plan.
# VERSION: 0.1.0
# AUTHORS: gh-platform

package terraform.tags

import rego.v1

required := {"Environment", "ManagedBy"}

# Resources commonly expected to carry ownership tags.
tagged_types := {
	"aws_s3_bucket",
	"aws_instance",
	"aws_lb",
	"aws_db_instance",
	"aws_ecs_service",
	"aws_lambda_function",
	"aws_sns_topic",
	"aws_sqs_queue",
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type in tagged_types
	is_create_or_update(rc)
	tags := object.get(rc.change.after, "tags", {})
	tags != null
	some key in required
	not tags[key]
	msg := sprintf("%s (%s) missing required tag %q", [rc.address, rc.type, key])
}

is_create_or_update(rc) if {
	some action in rc.change.actions
	action in {"create", "update"}
}
