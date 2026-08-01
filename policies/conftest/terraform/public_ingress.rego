# FILE_NAME: public_ingress.rego
# DESCRIPTION: Deny security group rules that open SSH/RDP to the world.
# VERSION: 0.1.0
# AUTHORS: gh-platform

package terraform.network

import rego.v1

sensitive_ports := {22, 3389}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_security_group_rule"
	is_create_or_update(rc)
	rc.change.after.type == "ingress"
	world_cidr(rc.change.after)
	port_sensitive(rc.change.after)
	msg := sprintf("Security group rule %s opens a sensitive port to 0.0.0.0/0 or ::/0", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_vpc_security_group_ingress_rule"
	is_create_or_update(rc)
	world_cidr_v2(rc.change.after)
	port_sensitive_v2(rc.change.after)
	msg := sprintf("Security group ingress rule %s opens a sensitive port to the world", [rc.address])
}

is_create_or_update(rc) if {
	some action in rc.change.actions
	action in {"create", "update"}
}

world_cidr(after) if {
	some cidr in object.get(after, "cidr_blocks", [])
	cidr in {"0.0.0.0/0", "::/0"}
}

world_cidr(after) if {
	some cidr in object.get(after, "ipv6_cidr_blocks", [])
	cidr == "::/0"
}

world_cidr_v2(after) if {
	object.get(after, "cidr_ipv4", "") == "0.0.0.0/0"
}

world_cidr_v2(after) if {
	object.get(after, "cidr_ipv6", "") == "::/0"
}

port_sensitive(after) if {
	from := to_number(object.get(after, "from_port", -1))
	to := to_number(object.get(after, "to_port", -1))
	some p in sensitive_ports
	from <= p
	to >= p
}

port_sensitive_v2(after) if {
	from := to_number(object.get(after, "from_port", -1))
	to := to_number(object.get(after, "to_port", -1))
	some p in sensitive_ports
	from <= p
	to >= p
}
