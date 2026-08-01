# FILE_NAME: observability.rego
# DESCRIPTION: CloudWatch Logs retention and encryption baselines.
# VERSION: 0.2.0
# AUTHORS: gh-platform

package terraform.observability

import rego.v1
import data.terraform.util as util

# Production log groups must set finite retention (not null/0 forever)
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_cloudwatch_log_group"
	util.is_create_or_update(rc)
	tags := util.tags_of(rc)
	lower(object.get(tags, "Environment", "")) in {"prod", "production", "prd"}
	ret := object.get(util.after(rc), "retention_in_days", null)
	ret == null
	msg := sprintf("%s production log group must set retention_in_days", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_cloudwatch_log_group"
	util.is_create_or_update(rc)
	tags := util.tags_of(rc)
	lower(object.get(tags, "Environment", "")) in {"prod", "production", "prd"}
	ret := object.get(util.after(rc), "retention_in_days", null)
	ret == 0
	msg := sprintf("%s production log group retention_in_days=0 (never expire) is not allowed", [rc.address])
}

# Prod log groups should use KMS
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_cloudwatch_log_group"
	util.is_create_or_update(rc)
	kms := object.get(util.after(rc), "kms_key_id", null)
	kms == null
	tags := util.tags_of(rc)
	lower(object.get(tags, "Environment", "")) in {"prod", "production", "prd"}
	msg := sprintf("%s production log group should set kms_key_id", [rc.address])
}
