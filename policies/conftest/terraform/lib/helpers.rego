# FILE_NAME: helpers.rego
# DESCRIPTION: Shared helpers for gh-platform Terraform/OpenTofu Conftest policies.
# VERSION: 0.1.0
# AUTHORS: gh-platform

package terraform.util

import rego.v1

is_create_or_update(rc) if {
	some action in rc.change.actions
	action in {"create", "update"}
}

is_create(rc) if {
	some action in rc.change.actions
	action == "create"
}

after(rc) := rc.change.after

# Prefer tags_all (provider-merged); fall back to tags.
tags_of(rc) := t if {
	t := object.get(rc.change.after, "tags_all", null)
	t != null
} else := t if {
	t := object.get(rc.change.after, "tags", {})
	t != null
} else := {}

has_required_tags(rc, required) if {
	tags := tags_of(rc)
	every key in required {
		tags[key]
	}
}

world_cidrs := {"0.0.0.0/0", "::/0"}

cidr_is_world(cidr) if {
	cidr in world_cidrs
}

port_in_range(from, to, port) if {
	to_number(from) <= port
	to_number(to) >= port
}
