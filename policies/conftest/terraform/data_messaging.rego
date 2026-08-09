# FILE_NAME: data_messaging.rego
# DESCRIPTION: Secrets Manager, SNS, SES, EventBridge, GuardDuty baselines.
# VERSION: 0.2.1
# AUTHORS: gh-platform

package terraform.data

import rego.v1
import data.terraform.util as util

# Secrets Manager: prefer KMS CMK when kms_key_id empty in prod
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_secretsmanager_secret"
	util.is_create_or_update(rc)
	kms := object.get(util.after(rc), "kms_key_id", null)
	kms == null
	tags := util.tags_of(rc)
	lower(object.get(tags, "Environment", "")) in {"prod", "production", "prd"}
	msg := sprintf("%s production secret should set kms_key_id (CMK)", [rc.address])
}

# Never put secret strings that look like private keys in secret_version from plan — if present after_unknown skip
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_secretsmanager_secret_version"
	util.is_create_or_update(rc)
	ss := object.get(util.after(rc), "secret_string", "")
	is_string(ss)
	startswith(ss, "-----BEGIN")
	msg := sprintf("%s embeds a PEM blob in plan — inject via CI secret / SSM, not VCS", [rc.address])
}

# Production secrets must keep a recovery window (forbid force-delete / 0-day recovery)
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_secretsmanager_secret"
	util.is_create_or_update(rc)
	tags := util.tags_of(rc)
	lower(object.get(tags, "Environment", "")) in {"prod", "production", "prd"}
	rw := object.get(util.after(rc), "recovery_window_in_days", 30)
	to_number(rw) == 0
	msg := sprintf("%s production secret must not set recovery_window_in_days=0", [rc.address])
}

# SNS: encryption required in production
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_sns_topic"
	util.is_create_or_update(rc)
	kms := object.get(util.after(rc), "kms_master_key_id", null)
	kms == null
	tags := util.tags_of(rc)
	lower(object.get(tags, "Environment", "")) in {"prod", "production", "prd"}
	msg := sprintf("%s production topic must set kms_master_key_id", [rc.address])
}

# SNS subscription: deny HTTP (unencrypted) protocol
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_sns_topic_subscription"
	util.is_create_or_update(rc)
	util.after(rc).protocol == "http"
	msg := sprintf("%s uses protocol=http — use https or sqs/lambda", [rc.address])
}

# EventBridge scheduler: deny flexible flexible_time_window without customer managed — skip
# GuardDuty detector should be enabled
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_guardduty_detector"
	util.is_create_or_update(rc)
	util.after(rc).enable == false
	msg := sprintf("%s GuardDuty detector must be enable=true", [rc.address])
}

# SES: configuration set should enable reputation metrics when present
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_sesv2_configuration_set"
	util.is_create_or_update(rc)
	some opts in object.get(util.after(rc), "reputation_options", [])
	opts.reputation_metrics_enabled == false
	msg := sprintf("%s should enable reputation_metrics_enabled", [rc.address])
}
