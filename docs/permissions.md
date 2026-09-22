# Jenkins AWS permissions

Configure a short-lived agent identity. Resolve account, region, ECR ARN and
instance ARN from your deployment; this specification is not a deployed policy.

| Actions | Scope |
| --- | --- |
| ecr:GetAuthorizationToken | * (API requires it) |
| ecr:BatchCheckLayerAvailability, ecr:InitiateLayerUpload, ecr:UploadLayerPart, ecr:CompleteLayerUpload, ecr:PutImage, ecr:DescribeImages | Only the Terraform ECR repository ARN |
| ssm:SendCommand | Target EC2 instance ARN and arn:aws:ssm:REGION::document/AWS-RunShellScript |
| ssm:GetCommandInvocation | * (no per-instance resource scope) |

RunShellScript executes as root. Restrict pipeline editing, parameters and
approvals to trusted maintainers. Do not grant AdministratorAccess as a shortcut.
The human operator separately needs Session Manager port-forwarding permissions.
Jenkins does not need permission to create/destroy Terraform infrastructure.
