# 4.3.0

* Upgrading to Jitsi version stable-11248
* Containers run rootless (uid 1000) as of stable-11146: the config/storage tree on the assets bucket is now chown'ed to 1000:1000 at boot, including files left behind by earlier versions, and the storage/transcriber directories are created up front
* CloudWatch logging blocks are inserted into the upstream compose files by service name instead of hardcoded line numbers, so they survive upstream compose file changes
* Bump oe-patterns-cdk-common 4.5.1 -> 4.5.2 (Lambda runtime python3.10 -> python3.13; AWS blocks creation of python3.10 functions since 2026-07-31)
* Fixed NLB UDP target groups always reporting unhealthy: UDP target groups now health-check on TCP 80 and the instance security group allows the NLB's health-check probes on TCP 80. Previously every JVB/Jigasi UDP target showed Target.FailedHealthChecks on all deployments (traffic still flowed because NLBs fail open).
* Upgrade devenv to 2.8.6 (pytest available in-container) and add CDK unit tests (`cdk/tests/unit`, run with `make test-unit`).

# 4.2.0

* Upgrading to Jitsi version stable-11031
* Fixing boto3 install failure on Ubuntu 24.04 AMI (PEP 668 externally-managed-environment)

# 4.1.1

* Upgrading to Ubuntu 24.04
* Upgrading to Jitsi version stable-10888
* FOSSonCloud rebranding

# 4.0.0

* Upgrading to Jitsi version stable-9823
* Upgrading to docker-based deployment
* Use NLB --> ALB instead of EC2/EIP
* Use ACM instead of Let's Encrypt for SSL
* Adding CustomDotEnvParameterArn parameter
* Adding CustomConfigJsParameterArn parameter
* Adding CustomInterfaceConfigJsParameterArn parameter

# 3.0.0

* Upgrading to Jitsi version 2.0.8960-1
* Upgrading to devenv container
* Upgrading to Ubuntu 22.04
* Upgrading to ASG common library (changes parameter names)
* Upgrade to CDK version 2.44.0
* Adding nginx logs to CloudWatch

# 2.2.0

* Upgrading to Jitsi version 2.0.6726-1

# 2.1.0

* Upgrade to CDK version 1.87.1
* Upgrading to Jitsi version 2.0.6433-1
* Fixing AppLogGroup permissions
* Adding prosody.err to CloudWatch logs
* Prosody cert permission fix
* updates to plf generation

# 2.0.0

* Upgrading to Jitsi version 2.0.6293-1
* Moving to common Makefile
* Upgrading VPC common library (changes parameter names)
* Disabling recording and live stream buttons
* Disable default apache site

# 1.0.4

* Fixing `make deploy` command

# 1.0.3

* Adding vpc domain for EIP

# 1.0.2

* Remove Let's Encrypt email param

# 1.0.1

* Tweak to Route 53 parameter and documentation

# 1.0.0

* Adding taskcat tests
* Run taskcat via GitHub Actions
* Linting fixes
* PLF config (WIP)

# 0.1.0

* Initial commit
* Move jitsi download to AMI build
