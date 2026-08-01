# FILE_NAME: s3_encryption.rego
# DESCRIPTION: Deny plans that create/update S3 buckets without any SSE configuration resource.
# VERSION: 0.1.0
# AUTHORS: gh-platform

package terraform.s3

import rego.v1

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket"
	is_create_or_update(rc)
	not encryption_in_plan
	msg := sprintf("S3 bucket %s created/updated but plan has no aws_s3_bucket_server_side_encryption_configuration", [rc.address])
}

is_create_or_update(rc) if {
	some action in rc.change.actions
	action in {"create", "update"}
}

encryption_in_plan if {
	some enc in input.resource_changes
	enc.type == "aws_s3_bucket_server_side_encryption_configuration"
	is_create_or_update(enc)
}
