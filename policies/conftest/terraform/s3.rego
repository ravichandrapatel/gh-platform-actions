# FILE_NAME: s3.rego
# DESCRIPTION: S3 security baselines for s3 / s3-bucket-notification modules.
# VERSION: 0.2.0
# AUTHORS: gh-platform

package terraform.s3

import rego.v1
import data.terraform.util as util

# Buckets in plan must be accompanied by SSE configuration.
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket"
	util.is_create_or_update(rc)
	not encryption_in_plan
	msg := sprintf("S3 bucket %s missing aws_s3_bucket_server_side_encryption_configuration in plan", [rc.address])
}

encryption_in_plan if {
	some enc in input.resource_changes
	enc.type == "aws_s3_bucket_server_side_encryption_configuration"
	util.is_create_or_update(enc)
}

# Public access block must not disable all protections.
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket_public_access_block"
	util.is_create_or_update(rc)
	after := util.after(rc)
	not after.block_public_acls
	msg := sprintf("%s must set block_public_acls=true", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket_public_access_block"
	util.is_create_or_update(rc)
	after := util.after(rc)
	not after.block_public_policy
	msg := sprintf("%s must set block_public_policy=true", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket_public_access_block"
	util.is_create_or_update(rc)
	after := util.after(rc)
	not after.ignore_public_acls
	msg := sprintf("%s must set ignore_public_acls=true", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket_public_access_block"
	util.is_create_or_update(rc)
	after := util.after(rc)
	not after.restrict_public_buckets
	msg := sprintf("%s must set restrict_public_buckets=true", [rc.address])
}

# Prefer AES256 or aws:kms — reject plaintext / empty algorithm.
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket_server_side_encryption_configuration"
	util.is_create_or_update(rc)
	some rule in object.get(util.after(rc), "rule", [])
	algo := object.get(object.get(rule, "apply_server_side_encryption_by_default", {}), "sse_algorithm", "")
	algo != ""
	not algo in {"AES256", "aws:kms"}
	msg := sprintf("%s uses unsupported sse_algorithm %q", [rc.address, algo])
}

# Versioning should not be explicitly suspended on create/update.
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket_versioning"
	util.is_create_or_update(rc)
	status := object.get(object.get(util.after(rc), "versioning_configuration", [{}])[0], "status", "")
	status == "Suspended"
	msg := sprintf("%s must not suspend versioning", [rc.address])
}
