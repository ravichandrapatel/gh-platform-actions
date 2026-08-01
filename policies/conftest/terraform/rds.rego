# FILE_NAME: rds.rego
# DESCRIPTION: RDS security baselines for the rds module.
# VERSION: 0.2.0
# AUTHORS: gh-platform

package terraform.rds

import rego.v1
import data.terraform.util as util

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_db_instance"
	util.is_create_or_update(rc)
	util.after(rc).storage_encrypted == false
	msg := sprintf("%s must set storage_encrypted=true", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_db_instance"
	util.is_create_or_update(rc)
	util.after(rc).publicly_accessible == true
	msg := sprintf("%s must not be publicly_accessible", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_db_instance"
	util.is_create_or_update(rc)
	util.after(rc).deletion_protection == false
	tags := util.tags_of(rc)
	lower(object.get(tags, "Environment", "")) in {"prod", "production", "prd"}
	msg := sprintf("%s in production must enable deletion_protection", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_db_instance"
	util.is_create_or_update(rc)
	util.after(rc).backup_retention_period == 0
	msg := sprintf("%s backup_retention_period must be > 0", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_db_instance"
	util.is_create_or_update(rc)
	util.after(rc).iam_database_authentication_enabled == false
	# advisory via deny only when tag RequireIAMAuth=true
	tags := util.tags_of(rc)
	tags.RequireIAMAuth == "true"
	msg := sprintf("%s tagged RequireIAMAuth but IAM DB auth disabled", [rc.address])
}
