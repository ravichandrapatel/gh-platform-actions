# FILE_NAME: compute.rego
# DESCRIPTION: EC2, Lambda, ECS, ECR, Step Functions security baselines.
# VERSION: 0.2.0
# AUTHORS: gh-platform

package terraform.compute

import rego.v1
import data.terraform.util as util

# EC2: no public IP by default on create when associate_public_ip_address=true without Bastion tag
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_instance"
	util.is_create_or_update(rc)
	after := util.after(rc)
	after.associate_public_ip_address == true
	tags := util.tags_of(rc)
	not tags.Bastion
	not lower(object.get(tags, "Role", "")) == "bastion"
	msg := sprintf("%s has public IP — set tag Bastion=true only for jump hosts", [rc.address])
}

# EC2: require IMDSv2
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_instance"
	util.is_create_or_update(rc)
	meta := object.get(util.after(rc), "metadata_options", [])
	count(meta) > 0
	some m in meta
	object.get(m, "http_tokens", "") == "optional"
	msg := sprintf("%s must use IMDSv2 (metadata_options.http_tokens=required)", [rc.address])
}

# Lambda: deny env vars that look like embedded secrets
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_lambda_function"
	util.is_create_or_update(rc)
	env := object.get(object.get(util.after(rc), "environment", [{}])[0], "variables", {})
	some key, _ in env
	regex.match(`(?i)(password|secret|api_?key|token|private_?key)`, key)
	msg := sprintf("%s env var %q looks like a secret — use Secrets Manager", [rc.address, key])
}

# Lambda: require X-Ray or at least not run as root — skip
# Require that reserved_concurrent_executions is not -1 weird — skip

# ECR: image scanning on push
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_ecr_repository"
	util.is_create_or_update(rc)
	scan := object.get(util.after(rc), "image_scanning_configuration", [])
	count(scan) > 0
	some s in scan
	s.scan_on_push == false
	msg := sprintf("%s must enable image_scanning_configuration.scan_on_push", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_ecr_repository"
	util.is_create_or_update(rc)
	scan := object.get(util.after(rc), "image_scanning_configuration", [])
	count(scan) == 0
	msg := sprintf("%s must configure image scanning on push", [rc.address])
}

# ECR: production repos should use IMMUTABLE tags
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_ecr_repository"
	util.is_create_or_update(rc)
	util.after(rc).image_tag_mutability == "MUTABLE"
	tags := util.tags_of(rc)
	lower(object.get(tags, "Environment", "")) in {"prod", "production", "prd"}
	msg := sprintf("%s production repo should use image_tag_mutability=IMMUTABLE", [rc.address])
}

# ECS task def: deny privileged containers
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_ecs_task_definition"
	util.is_create_or_update(rc)
	defs := json.unmarshal(util.after(rc).container_definitions)
	some c in defs
	c.privileged == true
	msg := sprintf("%s container %q sets privileged=true", [rc.address, object.get(c, "name", "?")])
}

# ECS task def: deny host network mode for Fargate-incompatible risky configs
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_ecs_task_definition"
	util.is_create_or_update(rc)
	util.after(rc).network_mode == "host"
	msg := sprintf("%s uses network_mode=host — prefer awsvpc", [rc.address])
}

# ECS service: no public IPs in production
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_ecs_service"
	util.is_create_or_update(rc)
	some net in object.get(util.after(rc), "network_configuration", [])
	net.assign_public_ip == true
	tags := util.tags_of(rc)
	lower(object.get(tags, "Environment", "")) in {"prod", "production", "prd"}
	msg := sprintf("%s production service assign_public_ip=true — use private subnets + NAT/ALB", [rc.address])
}

# Step Functions: logging level OFF denied when logging_configuration present
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_sfn_state_machine"
	util.is_create_or_update(rc)
	some log in object.get(util.after(rc), "logging_configuration", [])
	log.level == "OFF"
	msg := sprintf("%s logging_configuration.level=OFF — enable at least ERROR", [rc.address])
}
