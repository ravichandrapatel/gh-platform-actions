# FILE_NAME: organizations.rego
# DESCRIPTION: AWS Organizations / account vending baselines.
# VERSION: 0.2.0
# AUTHORS: gh-platform

package terraform.organizations

import rego.v1
import data.terraform.util as util

# Organization should enable all features (not CONSOLIDATED_BILLING only) when created
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_organizations_organization"
	util.is_create_or_update(rc)
	util.after(rc).feature_set == "CONSOLIDATED_BILLING"
	msg := sprintf("%s should use feature_set=ALL for SCPs and advanced org features", [rc.address])
}

# Accounts should have an email and name — always true in TF
# Deny creating accounts without close_on_deletion caution in prod tags — skip

# SCP / policy: deny empty content
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_organizations_policy"
	util.is_create_or_update(rc)
	content := object.get(util.after(rc), "content", "")
	content == ""
	msg := sprintf("%s organizations policy content is empty", [rc.address])
}

# Policy type SERVICE_CONTROL_POLICY should not be FullAWSAccess-style Allow * — heuristic
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_organizations_policy"
	util.is_create_or_update(rc)
	util.after(rc).type == "SERVICE_CONTROL_POLICY"
	doc := json.unmarshal(util.after(rc).content)
	allows_star_star(doc)
	msg := sprintf("%s SCP allows Action:* Resource:* — SCPs should constrain, not widen", [rc.address])
}

allows_star_star(doc) if {
	some stmt in stmt_list(doc)
	object.get(stmt, "Effect", "") == "Allow"
	action_star(stmt)
	resource_star(stmt)
}

stmt_list(doc) := doc.Statement if is_array(doc.Statement)
stmt_list(doc) := [doc.Statement] if is_object(doc.Statement)

action_star(stmt) if stmt.Action == "*"
action_star(stmt) if {
	some a in stmt.Action
	a == "*"
}

resource_star(stmt) if stmt.Resource == "*"
resource_star(stmt) if {
	some r in stmt.Resource
	r == "*"
}
