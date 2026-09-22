# Incident API — Jenkins release engineering

Builds a chosen application commit, runs unit and container smoke tests,
publishes an immutable ECR tag and deploys by image digest through SSM.
Maintainer: Omprakash Kasaraneni.

**Status:** Jenkins build #4 passed nine application tests, built and smoke-tested
the image, published to ECR, and deployed a healthy release to EC2 through SSM
after manual approval. Direct API health, create and list checks passed on EC2.
Terraform cleanup completed: all 12 managed resources were destroyed after verification.
The demo is no longer live. Rollback testing and credential deletion verification remain pending.

## Prerequisites

A dedicated trusted Linux x86_64 Jenkins agent labeled `docker-aws` must have
Docker, Git, Python 3.10+ and AWS CLI v2. Install Jenkins Pipeline and Git plugins.
Configure this repository as Pipeline from SCM with script path `Jenkinsfile`.
The verified setup runs the controller and a custom inbound agent on Docker Desktop.
The agent image is defined in [agent/Dockerfile](agent/Dockerfile).
Create a Jenkins **Username with password** credential with ID
`aws-incident-deployer`: username = AWS access key ID, password = secret access key.
Use the dedicated IAM deployment user's scoped permissions, not root credentials.
The Jenkinsfile binds this credential only during publishing and deployment.
For an EC2-hosted agent, prefer an instance role and adapt the credential bindings.
The Terraform host role belongs to the deployment target, not the Jenkins agent.
See [permissions](docs/permissions.md). Never run untrusted pull requests on an
agent with Docker or deployment permissions.

## First build

1. Publish this repository and docker-deployment. For private app source,
   configure credentialsId in the application checkout's userRemoteConfigs.
2. Run once to load job parameters if needed. An empty APP_COMMIT is rejected.
3. Set APP_COMMIT to the full app commit SHA; leave DEPLOY=false to run checks.
4. Once Terraform apply and host readiness succeed, set AWS_REGION, ECR_URL and
   INSTANCE_ID from its outputs. Enable DEPLOY.
5. Review the digest and target at the approval step. After release, inspect
   archived image.txt and deployment-result.json and verify through an SSM tunnel.

App checkout points to `omprakash2499/docker-deployment`. Update it if renamed.
This version supports commercial AWS regions, not China/GovCloud. ECR tags use
the commit plus build number; deployment uses the resulting immutable digest.

## Release and rollback

release.sh uses an exclusive host lock. A candidate runs on loopback port
18080 against the existing database volume. Only after health succeeds does the
old container stop and the replacement start on 8080. A failed switch attempts
to restart the previous container and fails the build. There is a short outage;
this is not zero-downtime or blue/green traffic switching.

The candidate shares the database. Only backward-compatible schema changes are
suitable; this first version performs no migration. Image rollback does not
restore database contents. Save the previous successful digest for rollback.
From this repository on the trusted agent, set AWS_REGION, INSTANCE_ID and
DEPLOY_IMAGE (the previous ECR URL@sha256 digest), then run:

```bash
python3 scripts/deploy.py
```

Exercise failed-candidate behavior in a disposable demo and verify the old
version remains available. Exercise a failure after the container switch and
capture actual restoration logs before claiming automatic rollback is tested.
An `incident-previous` residue blocks a later release for investigation.

If Jenkins or the client times out, inspect the printed SSM command ID before
retrying: the remote command may still be running.

## Limits and evidence

ECR scan-on-push is informational; there is no vulnerability-threshold gate yet.
Base image digests and transitive dependencies are not fully locked. Images are
retained on the agent/host and ECR; inspect disk usage and remove old versions
deliberately, retaining rollback images. Central logging, alerts and automated
backup/restore are future work. Save actual build logs, digests, health responses
and rollback results; never claim measured savings or availability without data.
See docs/validation.md for checks actually run.

## Verified deployment evidence

See the [validation record](docs/validation.md) and [screenshot gallery](docs/screenshots/README.md).

![Jenkins release succeeded](docs/screenshots/08-aws-deployment-success.png)

![EC2 API verification](docs/screenshots/11-ec2-api-verification.png)
