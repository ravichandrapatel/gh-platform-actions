# FILE_NAME: edge.rego
# DESCRIPTION: ALB, CloudFront, ACM, and Route53 security baselines.
# VERSION: 0.2.0
# AUTHORS: gh-platform

package terraform.edge

import rego.v1
import data.terraform.util as util

# ALB listeners: production HTTP should redirect to HTTPS
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_lb_listener"
	util.is_create_or_update(rc)
	after := util.after(rc)
	after.protocol == "HTTP"
	not http_redirect(after)
	tags := util.tags_of(rc)
	lower(object.get(tags, "Environment", "")) in {"prod", "production", "prd"}
	msg := sprintf("%s production HTTP listener should redirect to HTTPS", [rc.address])
}

http_redirect(after) if {
	some d in object.get(after, "default_action", [])
	d.type == "redirect"
	object.get(d.redirect, "protocol", "") == "HTTPS"
}

# HTTPS listeners must specify a certificate
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_lb_listener"
	util.is_create_or_update(rc)
	after := util.after(rc)
	after.protocol == "HTTPS"
	object.get(after, "certificate_arn", "") in {null, ""}
	msg := sprintf("%s HTTPS listener missing certificate_arn", [rc.address])
}

# CloudFront: deny viewer protocol allow-all
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_cloudfront_distribution"
	util.is_create_or_update(rc)
	some beh in object.get(util.after(rc), "default_cache_behavior", [])
	beh.viewer_protocol_policy == "allow-all"
	msg := sprintf("%s default_cache_behavior viewer_protocol_policy=allow-all — use redirect-to-https", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_cloudfront_distribution"
	util.is_create_or_update(rc)
	util.after(rc).enabled == true
	waf := object.get(util.after(rc), "web_acl_id", "")
	waf == ""
	tags := util.tags_of(rc)
	lower(object.get(tags, "Environment", "")) in {"prod", "production", "prd"}
	msg := sprintf("%s production CloudFront should attach a WAF web_acl_id", [rc.address])
}

# ACM: deny certs without domain validation method DNS for public certs
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_acm_certificate"
	util.is_create_or_update(rc)
	after := util.after(rc)
	object.get(after, "certificate_authority_arn", null) == null
	object.get(after, "private_certificate_authority_arn", null) == null
	after.validation_method == "EMAIL"
	msg := sprintf("%s should use validation_method=DNS (not EMAIL)", [rc.address])
}
