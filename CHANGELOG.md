# Unreleased
------------

4.0.0-stable-9823
-----------------
* Upgrading to Jitsi version stable-9823
* Upgrading to docker-based deployment
* Use NLB --> ALB instead of EC2/EIP
* Use ACM instead of Let's Encrypt for SSL
* Adding CustomDotEnvParameterArn parameter
* Adding CustomConfigJsParameterArn parameter
* Adding CustomInterfaceConfigJsParameterArn parameter

3.0.0
-----
* Upgrading to Jitsi version 2.0.8960-1
* Upgrading to devenv container
* Upgrading to Ubuntu 22.04
* Upgrading to ASG common library (changes parameter names)
* Upgrade to CDK version 2.44.0
* Adding nginx logs to CloudWatch

2.2.0
-----
* Upgrading to Jitsi version 2.0.6726-1

2.1.0
-----
* Upgrade to CDK version 1.87.1
* Upgrading to Jitsi version 2.0.6433-1
* Fixing AppLogGroup permissions
* Adding prosody.err to CloudWatch logs
* Prosody cert permission fix
* updates to plf generation

2.0.0
-----
* Upgrading to Jitsi version 2.0.6293-1
* Moving to common Makefile
* Upgrading VPC common library (changes parameter names)
* Disabling recording and live stream buttons
* Disable default apache site

1.0.4
-----
* Fixing `make deploy` command

1.0.3
-----
* Adding vpc domain for EIP

1.0.2
-----
* Remove Let's Encrypt email param

1.0.1
-----
* Tweak to Route 53 parameter and documentation

1.0.0
-----
* Adding taskcat tests
* Run taskcat via GitHub Actions
* Linting fixes
* PLF config (WIP)

0.1.0
-----
* Initial commit
* Move jitsi download to AMI build
