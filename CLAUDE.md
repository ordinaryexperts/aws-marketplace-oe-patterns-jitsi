# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AWS Marketplace pattern that deploys a production-ready Jitsi Meet instance using CloudFormation/CDK. The project consists of:

1. **Custom AMI** built with Packer (Ubuntu 22.04 with Jitsi Meet pre-installed)
2. **CDK Infrastructure** (Python) that synthesizes to CloudFormation templates
3. **Product Listing Framework (PLF)** configuration for AWS Marketplace publishing

The infrastructure includes: VPC, EC2 Auto Scaling Groups, Network Load Balancer (NLB), Application Load Balancer (ALB), Route53, ACM, S3, Secrets Manager, SSM, and CloudWatch.

## Upgrade Workflow

For upgrading the upstream Jitsi version, follow the process in [aws-marketplace-utilities/UPGRADE.md](https://github.com/ordinaryexperts/aws-marketplace-utilities/blob/main/UPGRADE.md).

## Development Environment

All development is done inside Docker containers via docker-compose to ensure consistency:

- `devenv` service: Main development environment with CDK, AWS CLI, Python, and all required tools
- `ami` service: Packer environment for building custom AMIs

**Never run CDK, Packer, or other build commands directly on the host.** Always use `make` targets which wrap docker-compose.

### Using AWS Profiles

The docker-compose setup passes through AWS environment variables, so you can use AWS profiles directly:

```bash
AWS_PROFILE=oe-patterns-dev make ami-ec2-build
AWS_PROFILE=oe-patterns-dev make deploy
```

Alternatively, you can export the profile:
```bash
export AWS_PROFILE=oe-patterns-dev
make ami-ec2-build
```

## Common Commands

### Setup
First, download the common make targets:
```bash
make update-common
```

This downloads `common.mk` from the aws-marketplace-utilities repository (version 1.6.0), which contains most of the make targets used in this project.

### Build and Setup
- `make build` - Build the devenv Docker image
- `make rebuild` - Rebuild devenv without cache
- `make bash` - Start an interactive bash session in devenv container

### CDK Operations
- `make synth` - Synthesize CloudFormation template
- `make synth-to-file` - Synthesize template and save to `dist/template.yaml`
- `make diff` - Show differences between deployed stack and current code
- `make deploy` - Deploy the stack to AWS (dev environment with hardcoded parameters)
- `make destroy` - Destroy the deployed stack
- `make cdk-bootstrap` - Bootstrap CDK in the AWS account

### Testing
- `make lint` - Run linting checks
- `make test-main` - Run main integration test with taskcat (deploys actual stack)
- `make test-all` - Run all integration tests (multi-region)

### AMI Building
- `make ami-ec2-build` - Build AMI with Packer
- `make ami-ec2-copy AMI_ID=<id>` - Copy AMI to other regions
- `make ami-docker-bash` - Interactive bash session in AMI container
- `make ami-docker-build` - Build AMI Docker image
- `make ami-docker-rebuild` - Rebuild AMI Docker image without cache

### Product Listing Framework (PLF)
- `make gen-plf AMI_ID=<id> TEMPLATE_VERSION=<version>` - Generate PLF configuration
- `make plf AMI_ID=<id> TEMPLATE_VERSION=<version>` - Update product listing
- `make plf-skip-pricing` - Update PLF without updating pricing
- `make plf-skip-region` - Update PLF without updating region availability
- `make plf-skip-pricing-and-region` - Update PLF skipping both

### Publishing
- `make publish TEMPLATE_VERSION=<version>` - Publish CloudFormation template to S3
- `make publish-diagram TEMPLATE_VERSION=<version>` - Publish architecture diagram to S3

**Important:** Use `oe-patterns-dev` profile for publishing templates and diagrams to S3:
```bash
AWS_PROFILE=oe-patterns-dev make publish TEMPLATE_VERSION=x.y.z
AWS_PROFILE=oe-patterns-dev make publish-diagram TEMPLATE_VERSION=x.y.z
```

### AWS Marketplace Submission
- `make marketplace-validate` - Check product is ready for version submission
- `make marketplace-submit AMI_ID=<id> TEMPLATE_VERSION=<version>` - Submit a new version
- `make marketplace-status` - Check submission status

**Important:** Use `oe-patterns-prod` profile for Marketplace API calls (since the product is in that account):
```bash
AWS_PROFILE=oe-patterns-prod make marketplace-validate
AWS_PROFILE=oe-patterns-prod make marketplace-submit AMI_ID=ami-xxx TEMPLATE_VERSION=x.y.z
```

**Prerequisites for marketplace-submit:**
1. Run `make synth-to-file` to generate `dist/template.yaml`
2. Publish template and diagram using `oe-patterns-dev` profile first
3. Ensure `marketplace_config.yaml` has all required fields including `delivery_option` section
4. Add release notes to `CHANGELOG.md` with a `## x.y.z` section
5. Copy `diagram.png` from the architecture diagram file if needed

### Cleanup
- `make clean` - Clean up test resources
- `make clean-snapshots-tcat` - Clean up taskcat snapshots
- `make clean-logs-tcat` - Clean up taskcat logs
- `make clean-buckets-tcat` - Clean up taskcat S3 buckets
- `make clean-all-tcat` - Clean all taskcat resources
- `make clean-*-all-regions` - Various cleanup commands across all regions

## Architecture

### CDK Stack Structure

The main CDK stack (`cdk/jitsi/jitsi_stack.py`) is composed using reusable constructs from the `oe-patterns-cdk-common` library. Key components:

1. **Vpc** - Creates VPC or uses existing one via parameters
2. **Dns** - Route53 hosted zone integration (parameter-driven)
3. **Secret** - Secrets Manager for Jitsi credentials and configuration
4. **AssetsBucket** - S3 bucket for Jitsi assets
5. **Asg** - Auto Scaling Group with custom AMI
6. **Alb** - Application Load Balancer with ACM certificate (HTTP/HTTPS)
7. **Nlb** - Network Load Balancer (UDP ports + proxies HTTP/HTTPS to ALB)

### Unique Architecture: NLB + ALB Combination

Jitsi requires both UDP (for video streaming) and HTTP/HTTPS (for web interface). This is achieved by:

- **NLB** sits in front and handles:
  - UDP port 10000 (JVB - Jitsi Video Bridge)
  - UDP ports 20000-20040 (Jigasi - SIP gateway)
  - TCP ports 80/443 (proxied to ALB)
- **ALB** behind NLB handles:
  - HTTP/HTTPS with ACM certificate
  - Health checks
  - Target group management

This dual-load-balancer design allows SSL termination at ALB while supporting UDP traffic through NLB.

### AMI Configuration

The AMI is built via Packer (`packer/ami.json`) using `packer/ubuntu_2404_appinstall.sh`. It pre-installs:
- Jitsi Meet (stable-11031)
- Docker and Docker Compose
- CloudWatch agent
- AWS Systems Manager agent

The AMI ID is hardcoded in `cdk/jitsi/jitsi_stack.py` and must be updated when building new AMIs.

### User Data

EC2 instances run `cdk/jitsi/user_data.sh` on boot, which:
- Retrieves secrets from Secrets Manager
- Fetches custom configuration from SSM Parameters (if provided)
- Generates `.env` file with Jitsi configuration
- Creates optional `custom-config.js` and `custom-interface-config.js`
- Starts Jitsi Meet via Docker Compose
- Configures CloudWatch Logs

### Parameter-Driven Design

The stack uses CloudFormation parameters extensively. Key parameters:
- `DnsHostname` / `DnsRoute53HostedZoneName` - DNS configuration
- `AlbCertificateArn` - ACM certificate for HTTPS
- `AlbIngressCidr` - IP ranges allowed to access the site
- `AsgReprovisionString` - Forces ASG instance replacement when changed
- `CustomDotEnvParameterArn` - Optional SSM parameter for custom `.env` config
- `CustomConfigJsParameterArn` - Optional SSM parameter for custom Jitsi config
- `CustomInterfaceConfigJsParameterArn` - Optional SSM parameter for custom interface config

### Customization via SSM Parameters

Users can customize Jitsi without modifying the CloudFormation template by storing configuration in SSM Parameter Store Secure Strings:

1. **CustomDotEnvParameterArn** - Appends to `.env` file (e.g., `ENABLE_RECORDING=1`)
2. **CustomConfigJsParameterArn** - Creates `custom-config.js` file
3. **CustomInterfaceConfigJsParameterArn** - Creates `custom-interface-config.js` file

The ARN should include the version number (e.g., `arn:aws:ssm:...:parameter/name:1`) to enable rollback by changing version.

## Important Patterns

### Version Management
Template version is determined by:
1. `TEMPLATE_VERSION` environment variable (if set)
2. `git describe` output (in git repos)
3. Falls back to "CICD" in CI environments

### Secrets Management
Jitsi secrets are:
1. Generated via `Secret` construct in Secrets Manager
2. Retrieved by EC2 instances via IAM role permissions
3. User data script reads secrets and generates `.env` file

### AMI Management Workflow
When building a new AMI:
1. Run `make ami-ec2-build` to build in us-east-1
2. Run `make ami-ec2-copy AMI_ID=ami-xxx` to copy to other regions
3. Copy generated code block from output into `jitsi_stack.py`
4. Update `AMI_ID` and `AMI_NAME` constants at top of `jitsi_stack.py`

The stack includes an assertion to ensure `AMI_ID` matches `generated_ami_ids["us-east-1"]`.

### Resource Tagging
All resources are tagged via CDK's built-in tagging.

## Testing

Integration tests use [taskcat](https://github.com/aws-ia/taskcat), which:
1. Synthesizes the CloudFormation template
2. Deploys it to AWS with test parameters
3. Validates deployment succeeds
4. Cleans up resources

Test configuration:
- Main test: `test/main-test/.taskcat.yml` (us-east-1 only)
- All tests: `test/.taskcat.yml` (multi-region compatibility testing)

Tests run on:
- Every push to `develop` branch
- Pull requests to `develop`
- Weekly schedule (Mondays at 7:03pm UTC)

## Git Workflow

- Main branch: `develop` (not `main` or `master`)
- Use git-flow style releases: feature branches → develop → release/X.Y.Z → tags

## Dependencies

### Python CDK Dependencies
Defined in `cdk/setup.py`:
- `aws-cdk-lib==2.120.0`
- `constructs>=10.0.0,<11.0.0`
- `oe-patterns-cdk-common@4.1.4` (from GitHub, contains reusable constructs)

### Docker Base Image
`ordinaryexperts/aws-marketplace-patterns-devenv:2.5.3` - contains CDK, Python, AWS CLI, taskcat, and other tools.

## Files to Update When Releasing

1. `cdk/jitsi/jitsi_stack.py` - Update `AMI_ID`, `AMI_NAME`, and `generated_ami_ids` mapping
2. `plf_config.yaml` - Product listing metadata (auto-updated by PLF scripts)
3. `CHANGELOG.md` - Document changes
4. Git tag with version number

## Important Notes

- **Do not add Make commands to common.mk** - that file is managed in the aws-marketplace-utilities repo
- The `deploy` target in Makefile has hardcoded parameters for the dev environment
- Jitsi runs in Docker containers on the EC2 instance (not directly on the host)
- NLB has 50 listener limit, so Jigasi only supports ports 20000-20040 (not full 20000-20050 range)
