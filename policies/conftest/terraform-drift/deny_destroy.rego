# FILE_NAME: deny_destroy.rego
# DESCRIPTION: Block delete/replace on drift/* reconcile PRs (stamp path must stay non-destructive).
# VERSION: 0.1.0
# AUTHORS: gh-platform

package terraform.drift

import rego.v1

deny contains msg if {
	some rc in input.resource_changes
	some action in rc.change.actions
	action == "delete"
	msg := sprintf(
		"drift reconcile PR must not destroy %s (actions=%v); triage via Drift Report issue instead",
		[rc.address, rc.change.actions],
	)
}
