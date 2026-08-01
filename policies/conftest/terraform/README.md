# Terraform / OpenTofu Conftest policies

OPA policies evaluated by [`tofu-pipeline`](../../../docs/workflows/tofu-pipeline.yml) against `tofu show -json` plan output.

## Layout

| File | Package | Focus |
| --- | --- | --- |
| `lib/helpers.rego` | `terraform.util` | Shared helpers |
| `common_tags.rego` | `terraform.tags` | `Environment` + `ManagedBy` on tagged resources |
| `s3.rego` | `terraform.s3` | Encryption, public access block, versioning |
| `network.rego` | `terraform.network` | SG world ingress, VPC DNS/flow logs, Client VPN, subnets |
| `iam.rego` | `terraform.iam` | Wildcard admin, trust `Principal AWS=*` |
| `compute.rego` | `terraform.compute` | EC2/IMDSv2, Lambda secrets, ECR, ECS, Step Functions |
| `rds.rego` | `terraform.rds` | Encryption, public access, backups, deletion protection |
| `edge.rego` | `terraform.edge` | ALB TLS, CloudFront viewer/WAF, ACM DNS validation |
| `data_messaging.rego` | `terraform.data` | Secrets, SNS, SES, GuardDuty |
| `identity.rego` | `terraform.identity` | Cognito MFA/password/callbacks |
| `observability.rego` | `terraform.observability` | CloudWatch retention/KMS |
| `organizations.rego` | `terraform.organizations` | Org feature set, SCP content |

## Severity model

- **Always deny:** clear insecure configurations (world SSH/RDP, unencrypted RDS, S3 without SSE, IAM `*/*`, SNS `http`, etc.).
- **Production deny:** rules that check `tags.Environment` ∈ `prod|production|prd` (flow logs, Cognito MFA, SNS CMK, immutable ECR, etc.) so module defaults stay usable in non-prod.

## Local test

```bash
conftest test tfplan.json -p policies/conftest/terraform --all-namespaces
```

## Module coverage

See [MODULE_COVERAGE.md](MODULE_COVERAGE.md).
