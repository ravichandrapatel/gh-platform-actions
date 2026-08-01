# FILE_NAME: network.rego
# DESCRIPTION: VPC, subnet, SG, peering, and Client VPN security baselines.
# VERSION: 0.2.0
# AUTHORS: gh-platform

package terraform.network

import rego.v1
import data.terraform.util as util

sensitive_ports := {22, 3389, 3306, 5432, 1433, 6379, 9200, 27017}

# --- Security group rules (standalone rule resources) ---

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_security_group_rule"
	util.is_create_or_update(rc)
	after := util.after(rc)
	after.type == "ingress"
	world_open(after)
	port_sensitive(after)
	msg := sprintf("%s opens sensitive port to the world", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_vpc_security_group_ingress_rule"
	util.is_create_or_update(rc)
	after := util.after(rc)
	world_open_v2(after)
	port_sensitive_v2(after)
	msg := sprintf("%s opens sensitive port to the world", [rc.address])
}

# Inline ingress on aws_security_group (security-group / vpc modules)
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_security_group"
	util.is_create_or_update(rc)
	some ing in object.get(util.after(rc), "ingress", [])
	world_open_inline(ing)
	port_sensitive_inline(ing)
	msg := sprintf("%s inline ingress opens sensitive port to the world", [rc.address])
}

# Default SG should not be used as the primary module SG with world egress unrestricted — allow egress 0.0.0.0/0 (common) but deny ingress world on all protocols
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_security_group"
	util.is_create_or_update(rc)
	some ing in object.get(util.after(rc), "ingress", [])
	world_open_inline(ing)
	to_number(object.get(ing, "from_port", 0)) == 0
	to_number(object.get(ing, "to_port", 0)) == 0
	object.get(ing, "protocol", "") == "-1"
	msg := sprintf("%s allows unrestricted world ingress (protocol=-1)", [rc.address])
}

# VPC: enable DNS support/hostnames when creating VPC
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_vpc"
	util.is_create_or_update(rc)
	after := util.after(rc)
	after.enable_dns_support == false
	msg := sprintf("%s must keep enable_dns_support=true", [rc.address])
}

# Flow logs: if present, reject DISABLED traffic_type weirdness — require ACCEPT/ALL/REJECT
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_flow_log"
	util.is_create_or_update(rc)
	tt := object.get(util.after(rc), "traffic_type", "ALL")
	not tt in {"ACCEPT", "REJECT", "ALL"}
	msg := sprintf("%s has invalid traffic_type %q", [rc.address, tt])
}

# Production VPCs must enable flow logs in the same plan
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_vpc"
	util.is_create(rc)
	tags := util.tags_of(rc)
	lower(object.get(tags, "Environment", "")) in {"prod", "production", "prd"}
	not flow_log_in_plan
	msg := sprintf("%s production VPC create without aws_flow_log — set enable_flow_logs=true", [rc.address])
}

flow_log_in_plan if {
	some fl in input.resource_changes
	fl.type == "aws_flow_log"
	util.is_create_or_update(fl)
}

# VPC peering: reject accepter/requester DNS resolution left disabled only as warning via deny if allow_remote_vpc_dns_resolution explicitly false on both — skip soft prefs

# Client VPN: split tunnel preferred? Deny when transport is TCP with self-service portal open — keep: authorize all CIDRs carefully
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_ec2_client_vpn_authorization_rule"
	util.is_create_or_update(rc)
	after := util.after(rc)
	after.authorize_all_groups == true
	after.target_network_cidr == "0.0.0.0/0"
	msg := sprintf("%s authorizes all groups to 0.0.0.0/0 — tighten Client VPN authorization", [rc.address])
}

# Subnets: map_public_ip_on_launch on private-looking plans is caller's choice — deny only when true AND tag Tier/Type says private
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_subnet"
	util.is_create_or_update(rc)
	after := util.after(rc)
	after.map_public_ip_on_launch == true
	tags := util.tags_of(rc)
	lower_tier := lower(object.get(tags, "Tier", object.get(tags, "Type", "")))
	lower_tier in {"private", "data", "internal"}
	msg := sprintf("%s is tagged %q but map_public_ip_on_launch=true", [rc.address, lower_tier])
}

world_open(after) if {
	some cidr in object.get(after, "cidr_blocks", [])
	util.cidr_is_world(cidr)
}

world_open(after) if {
	some cidr in object.get(after, "ipv6_cidr_blocks", [])
	util.cidr_is_world(cidr)
}

world_open_v2(after) if {
	util.cidr_is_world(object.get(after, "cidr_ipv4", ""))
}

world_open_v2(after) if {
	util.cidr_is_world(object.get(after, "cidr_ipv6", ""))
}

world_open_inline(ing) if {
	some cidr in object.get(ing, "cidr_blocks", [])
	util.cidr_is_world(cidr)
}

port_sensitive(after) if {
	some p in sensitive_ports
	util.port_in_range(object.get(after, "from_port", -1), object.get(after, "to_port", -1), p)
}

port_sensitive_v2(after) if {
	some p in sensitive_ports
	util.port_in_range(object.get(after, "from_port", -1), object.get(after, "to_port", -1), p)
}

port_sensitive_inline(ing) if {
	some p in sensitive_ports
	util.port_in_range(object.get(ing, "from_port", -1), object.get(ing, "to_port", -1), p)
}
