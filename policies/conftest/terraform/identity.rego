# FILE_NAME: identity.rego
# DESCRIPTION: Cognito and Identity Center baselines.
# VERSION: 0.2.0
# AUTHORS: gh-platform

package terraform.identity

import rego.v1
import data.terraform.util as util

# Cognito: production pools must not disable MFA
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_cognito_user_pool"
	util.is_create_or_update(rc)
	mfa := object.get(util.after(rc), "mfa_configuration", "OFF")
	mfa == "OFF"
	tags := util.tags_of(rc)
	lower(object.get(tags, "Environment", "")) in {"prod", "production", "prd"}
	msg := sprintf("%s production pool mfa_configuration=OFF — set OPTIONAL or ON", [rc.address])
}

# Cognito: password policy minimum length
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_cognito_user_pool"
	util.is_create_or_update(rc)
	some pol in object.get(util.after(rc), "password_policy", [])
	to_number(object.get(pol, "minimum_length", 0)) < 12
	msg := sprintf("%s password_policy.minimum_length must be >= 12", [rc.address])
}

# Cognito client: deny explicit auth flows allowing USER_PASSWORD_AUTH without SRP in prod — soft
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_cognito_user_pool_client"
	util.is_create_or_update(rc)
	some flow in object.get(util.after(rc), "explicit_auth_flows", [])
	flow == "ALLOW_USER_PASSWORD_AUTH"
	tags := util.tags_of(rc)
	lower(object.get(tags, "Environment", "")) in {"prod", "production", "prd"}
	msg := sprintf("%s production client allows USER_PASSWORD_AUTH — prefer SRP/custom auth", [rc.address])
}

# Cognito client: generate secret for confidential clients only — skip
# Prevent callback URLs with http:// (except localhost)
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_cognito_user_pool_client"
	util.is_create_or_update(rc)
	some url in object.get(util.after(rc), "callback_urls", [])
	startswith(url, "http://")
	not startswith(url, "http://localhost")
	msg := sprintf("%s callback_urls contains insecure http URL %q", [rc.address, url])
}
