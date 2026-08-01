# FILE_NAME: iam.rego
# DESCRIPTION: IAM / SSO permission-set baselines for iam, permission-set, account-assignment modules.
# VERSION: 0.2.0
# AUTHORS: gh-platform

package terraform.iam

import rego.v1
import data.terraform.util as util

# Deny inline/role policies with Action "*" and Resource "*"
deny contains msg if {
	some rc in input.resource_changes
	rc.type in {"aws_iam_policy", "aws_iam_role_policy"}
	util.is_create_or_update(rc)
	doc := policy_document(util.after(rc))
	wildcard_admin(doc)
	msg := sprintf("%s grants Action:* on Resource:* — split least-privilege statements", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_ssoadmin_permission_set_inline_policy"
	util.is_create_or_update(rc)
	doc := json.unmarshal(util.after(rc).inline_policy)
	wildcard_admin(doc)
	msg := sprintf("%s SSO inline policy is wildcard admin — tighten permission set", [rc.address])
}

# IAM roles must have an assume-role policy (present on create)
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_iam_role"
	util.is_create_or_update(rc)
	not util.after(rc).assume_role_policy
	msg := sprintf("%s missing assume_role_policy", [rc.address])
}

# Reject assume-role policies that allow Principal AWS "*"
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_iam_role"
	util.is_create_or_update(rc)
	doc := json.unmarshal(util.after(rc).assume_role_policy)
	some stmt in statements(doc)
	principal_aws_star(stmt)
	msg := sprintf("%s trust policy allows Principal AWS=* — pin to account/service", [rc.address])
}

policy_document(after) := doc if {
	is_string(after.policy)
	doc := json.unmarshal(after.policy)
} else := doc if {
	doc := after.policy
}

statements(doc) := doc.Statement if {
	is_array(doc.Statement)
} else := [doc.Statement] if {
	is_object(doc.Statement)
} else := []

wildcard_admin(doc) if {
	some stmt in statements(doc)
	effect_allow(stmt)
	action_star(stmt)
	resource_star(stmt)
}

effect_allow(stmt) if {
	object.get(stmt, "Effect", "Allow") == "Allow"
}

action_star(stmt) if {
	stmt.Action == "*"
}

action_star(stmt) if {
	some a in stmt.Action
	a == "*"
}

resource_star(stmt) if {
	stmt.Resource == "*"
}

resource_star(stmt) if {
	some r in stmt.Resource
	r == "*"
}

principal_aws_star(stmt) if {
	p := object.get(stmt, "Principal", {})
	p.AWS == "*"
}

principal_aws_star(stmt) if {
	p := object.get(stmt, "Principal", {})
	some a in p.AWS
	a == "*"
}
