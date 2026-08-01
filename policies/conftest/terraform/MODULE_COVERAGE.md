# Module → policy coverage (`gh-platform-modules`)

Policies are resource-type based (plan JSON), not module-path based. Every root module’s AWS resources are in scope.

| Module | Primary resources | Policy packages |
| --- | --- | --- |
| `account-assignment` | `aws_ssoadmin_account_assignment` | `tags` |
| `acm` | `aws_acm_certificate` | `tags`, `edge` |
| `alb` | `aws_lb`, listeners, TGs | `tags`, `edge`, `network` |
| `alb-listener-rule` | `aws_lb_listener_rule` | `edge` |
| `alb-target-group` | `aws_lb_target_group` | `tags`, `edge` |
| `alb-target-group-attachment` | attachment | (structural) |
| `client-vpn` | Client VPN endpoint/auth/routes | `tags`, `network` |
| `cloudfront` | distribution, OAC/OAI | `tags`, `edge` |
| `cloudwatch-logs` | log group | `tags`, `observability` |
| `cognito-user-pool` | user pool | `tags`, `identity` |
| `cognito-user-pool-client` | app client | `identity` |
| `cognito-user-pool-domain` | domain | `identity` |
| `ec2-instance` | instance | `tags`, `compute` |
| `ecr` | repository, lifecycle | `tags`, `compute` |
| `ecs-cluster` | cluster | `tags`, `compute` |
| `ecs-service` | service, task def, scaling | `tags`, `compute`, `observability` |
| `eventbridge-rule` | event rule/target | `data` |
| `eventbridge-scheduler` | schedule | `tags`, `data` |
| `guardduty-detector` | detector | `tags`, `data` |
| `guardduty-malware-protection-plan` | malware plan | `data` |
| `iam` | roles, policies, instance profile | `tags`, `iam` |
| `iam-saml-provider` | SAML provider | `iam` |
| `identity-center-*` / `identitystore-group` | Identity Center / Identity Store | `tags`, `iam` |
| `lambda` | function | `tags`, `compute` |
| `management-organizations` / `organizations*` | org, OU, account, policies | `tags`, `organizations` |
| `permission-set` | SSO permission sets | `tags`, `iam` |
| `rds` | DB instance + subnet/param/option groups | `tags`, `rds` |
| `route53*` | zones, records, ACM validation | `tags`, `edge` |
| `s3` | bucket + encryption/PAB/versioning/… | `tags`, `s3` |
| `s3-bucket-notification` | notification + lambda permission | `s3`, `compute` |
| `secrets-manager` | secret / version / rotation | `tags`, `data` |
| `security-group` | security group | `tags`, `network` |
| `ses-*` / `sesv2-configuration-set` | SES identities / config sets | `tags`, `data` |
| `sns-topic` | topic, policy, subscription | `tags`, `data` |
| `step-functions` | state machine | `tags`, `compute` |
| `tagging` | (tag map helper — no AWS resources) | n/a (consumed via tags on other modules) |
| `vpc` | VPC, subnets, NAT, endpoints, flow logs | `tags`, `network`, `observability`, `iam` |
| `vpc-peering` | peering + routes | `tags`, `network` |

`tagging` is a pure composition helper; enforce tags on the resources that consume `module.tags.tags`.
