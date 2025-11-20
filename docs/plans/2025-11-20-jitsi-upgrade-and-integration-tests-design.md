# Jitsi Upgrade and Integration Tests Design

**Date:** 2025-11-20
**Author:** Claude Code
**Status:** Approved

## Overview

This design covers a comprehensive upgrade of the Jitsi AWS Marketplace pattern, including:
1. Upgrading runtime environment components (Jitsi, Ubuntu, devenv, oe-commons)
2. Adding a pytest-based integration test framework similar to the mastodon project

## Current State

- **Jitsi:** stable-9823 (November 12, 2024)
- **Ubuntu:** 22.04.4 LTS
- **devenv:** 2.5.3
- **oe-patterns-cdk-common:** 4.1.4
- **Testing:** taskcat only (no integration tests)

## Target State

- **Jitsi:** stable-10590 (October 20, 2025 - latest stable)
- **Ubuntu:** 24.04 LTS
- **devenv:** 2.8.0 (from mastodon project)
- **oe-patterns-cdk-common:** Latest tagged release
- **Testing:** taskcat + pytest integration tests with multi-user scenarios

## Components to Update

### 1. Dockerfile
Update devenv version:
```dockerfile
FROM ordinaryexperts/aws-marketplace-patterns-devenv:2.8.0
```

### 2. cdk/setup.py
Update oe-patterns-cdk-common to latest tag:
```python
f"oe-patterns-cdk-common@git+https://github.com/ordinaryexperts/aws-marketplace-oe-patterns-cdk-common@X.Y.Z"
```

### 3. Packer Configuration

**packer/ami.json:**
- Update source AMI to Ubuntu 24.04 base image
- Reference new install script filename

**packer/ubuntu_2204_appinstall.sh:**
- Rename to `ubuntu_2404_appinstall.sh`
- Update line 118: `JITSI_VERSION=stable-10590`

Note: The upstream scripts (`ubuntu_2204_2404_preinstall.sh` and `ubuntu_2204_2404_postinstall.sh`) already support both Ubuntu versions.

### 4. CDK Stack
**cdk/jitsi/jitsi_stack.py:**
- Update `AMI_ID` constant
- Update `AMI_NAME` constant
- Update `generated_ami_ids` mapping with new AMI IDs for all regions

### 5. Documentation
- **README.md:** Update version information in Technical Details section
- **CHANGELOG.md:** Document all upgrades and new integration tests

## New Integration Test Framework

### Test Structure
```
test/integration/
├── base_integration_test.py    # Reusable base class from mastodon
├── conftest.py                 # Pytest fixtures (AWS clients, config)
├── config.yaml                 # Jitsi-specific test configuration
├── pytest.ini                  # Pytest settings (markers, timeouts)
├── requirements.txt            # Python dependencies
├── test_health.py              # Health & infrastructure tests
├── test_workflows.py           # UI/workflow tests with Playwright
└── README.md                   # Test documentation
```

### Test Levels

#### Level 1: Health & Infrastructure Tests (test_health.py)

**TestJitsiHealth:**
- `test_https_accessible()` - HTTPS access validation
- `test_health_endpoint()` - Test `/elb-check` endpoint (not `/health`)
- `test_response_time()` - Response time < 5 seconds
- `test_ssl_certificate()` - SSL certificate validation
- `test_security_headers()` - X-Frame-Options, X-Content-Type-Options

**TestJitsiInfrastructure:**
- `test_cloudformation_stack_exists()` - Stack status validation
- `test_stack_outputs()` - Required outputs present
- `test_ec2_instance_running()` - Instance health
- `test_instance_has_correct_ami()` - AMI validation
- `test_nlb_health()` - Network Load Balancer health
- `test_alb_health()` - Application Load Balancer health

#### Level 2: Application Tests (test_health.py)

**TestJitsiApplication:**
- `test_homepage_loads()` - Jitsi Meet homepage renders
- `test_javascript_bundle_loads()` - Jitsi JS bundle present
- `test_webrtc_config_present()` - WebRTC configuration available

#### Level 3: UI/Workflow Tests (test_workflows.py)

**TestJitsiBasicWorkflows:**
- `test_homepage_loads()` - Homepage renders correctly
- `test_meeting_room_creation()` - Can generate meeting room URLs
- `test_join_meeting_page()` - Join meeting page renders

**TestJitsiMultiUser:**

1. **test_two_users_join_meeting** - P2P Mode Validation
   - Start: 2 users join same meeting room
   - Verify: Peer-to-peer WebRTC connection established
   - Verify: Each user sees the other participant
   - Verify: Video/audio indicators appear
   - Duration: ~30-45 seconds

2. **test_three_users_join_meeting** - JVB Mode Validation
   - Start: 3 users join same meeting room
   - Verify: Jitsi Videobridge (JVB) mode activated
   - Verify: All 3 participants see each other
   - Verify: Participant count = 3
   - Duration: ~60-90 seconds

3. **test_p2p_to_jvb_transition** - Critical Architecture Test
   - Start: 2 users join (P2P mode)
   - Verify: P2P connection established
   - Action: 3rd user joins
   - Verify: Smooth transition to JVB mode
   - Verify: All 3 participants remain connected after switch
   - Verify: No dropped connections during mode transition
   - **This is the most important test** - validates Jitsi's architectural mode switch
   - Duration: ~90-120 seconds

### Jitsi Architecture Note

Jitsi Meet has two operational modes:
- **2 participants:** Peer-to-peer (P2P) - Direct WebRTC between clients
- **3+ participants:** JVB (Videobridge) - Media routed through server

The transition test validates both modes work and the switch is seamless.

### Test Configuration (config.yaml)

```yaml
application:
  name: "Jitsi Meet"
  health_endpoint: "/elb-check"
  expected_version: "stable-10590"

aws:
  region: "us-east-1"
  stack_name: "oe-patterns-jitsi-dylan"

test:
  timeout: 30
  retry_attempts: 3
  retry_delay: 2

urls:
  base_url: "https://jitsi-dylan.dev.patterns.ordinaryexperts.com"
```

### Makefile Targets

Add these targets to the project Makefile:

```makefile
test-integration: build
	docker compose run -w /code/test/integration --rm devenv pytest test_health.py -v

test-integration-health: build
	docker compose run -w /code/test/integration --rm devenv pytest test_health.py::TestJitsiHealth -v

test-integration-infrastructure: build
	docker compose run -w /code/test/integration --rm devenv pytest test_health.py::TestJitsiInfrastructure -v

test-integration-ui: build
	docker compose run -w /code/test/integration --rm devenv pytest test_workflows.py -v

test-integration-all: build
	docker compose run -w /code/test/integration --rm devenv pytest -v
```

## Implementation Workflow

### Phase 1: Find Latest Versions & Update Dependencies

1. Query oe-patterns-cdk-common for latest tag:
   ```bash
   git ls-remote --tags https://github.com/ordinaryexperts/aws-marketplace-oe-patterns-cdk-common | sort -V | tail -5
   ```

2. Update `Dockerfile` with devenv 2.8.0

3. Update `cdk/setup.py` with latest oe-patterns-cdk-common tag

4. Build new devenv container:
   ```bash
   make build
   ```

5. Test CDK synthesis works:
   ```bash
   make synth
   ```

### Phase 2: Update Packer for Ubuntu 24.04 + Jitsi stable-10590

1. Find Ubuntu 24.04 LTS base AMI ID for us-east-1:
   ```bash
   aws ec2 describe-images \
     --owners 099720109477 \
     --filters "Name=name,Values=ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*" \
     --query 'Images | sort_by(@, &CreationDate) | [-1].[ImageId,Name,CreationDate]'
   ```

2. Update `packer/ami.json` with new base AMI

3. Rename file:
   ```bash
   git mv packer/ubuntu_2204_appinstall.sh packer/ubuntu_2404_appinstall.sh
   ```

4. Update Jitsi version in `packer/ubuntu_2404_appinstall.sh` line 118:
   ```bash
   JITSI_VERSION=stable-10590
   ```

5. Update `packer/ami.json` to reference `ubuntu_2404_appinstall.sh`

### Phase 3: Build & Deploy New AMI

1. Build AMI:
   ```bash
   make ami-ec2-build
   ```
   This builds in us-east-1 and outputs the AMI ID.

2. Copy AMI to all regions:
   ```bash
   make ami-ec2-copy AMI_ID=ami-xxxxxxxxx
   ```
   This generates the code block for `generated_ami_ids`.

3. Update `cdk/jitsi/jitsi_stack.py`:
   - Update `AMI_ID` constant (line 44)
   - Update `AMI_NAME` constant (line 45)
   - Replace `generated_ami_ids` dictionary (lines 46-72)

4. Deploy to dev environment:
   ```bash
   make deploy
   ```

5. **PAUSE: Manual Verification by User**

   Test the following manually:
   - [ ] Navigate to Jitsi URL, homepage loads
   - [ ] Create a test meeting room
   - [ ] Open meeting in 2 browser tabs (test P2P mode)
   - [ ] Verify both users see each other
   - [ ] Open meeting in 3rd browser tab (test P2P → JVB transition)
   - [ ] Verify all 3 users see each other
   - [ ] Check audio/video quality
   - [ ] Review CloudWatch logs for errors
   - [ ] Test custom SSM parameter config still works
   - [ ] Verify SSL certificate is valid

   If any issues are found, investigate and fix before proceeding to Phase 4.

### Phase 4: Create Integration Test Framework

**After manual verification passes:**

1. Create directory structure:
   ```bash
   mkdir -p test/integration
   ```

2. Copy base files from mastodon project:
   ```bash
   # Copy these files with minimal modifications
   cp ../aws-marketplace-oe-patterns-mastodon/test/integration/base_integration_test.py test/integration/
   cp ../aws-marketplace-oe-patterns-mastodon/test/integration/conftest.py test/integration/
   cp ../aws-marketplace-oe-patterns-mastodon/test/integration/pytest.ini test/integration/
   cp ../aws-marketplace-oe-patterns-mastodon/test/integration/requirements.txt test/integration/
   ```

3. Create Jitsi-specific files:
   - `test/integration/test_health.py` - Adapt health tests for Jitsi
     - Change health endpoint to `/elb-check`
     - Remove Mastodon-specific API tests
     - Add NLB health checks

   - `test/integration/test_workflows.py` - Write Jitsi multi-user tests
     - Implement 2-user P2P test
     - Implement 3-user JVB test
     - Implement P2P → JVB transition test

   - `test/integration/config.yaml` - Jitsi configuration
     - Set health_endpoint to `/elb-check`
     - Set expected version to `stable-10590`
     - Set base_url to dev Jitsi instance

   - `test/integration/README.md` - Jitsi-specific documentation
     - Explain P2P vs JVB modes
     - Document multi-user test scenarios
     - Include setup instructions

4. Add Makefile targets:
   ```makefile
   test-integration: build
   test-integration-health: build
   test-integration-infrastructure: build
   test-integration-ui: build
   test-integration-all: build
   ```

5. Install Playwright browsers in devenv:
   ```bash
   docker compose run --rm devenv playwright install chromium
   ```

### Phase 5: Automated Test & Validate

1. Run taskcat integration test (deploys full stack):
   ```bash
   make test-main
   ```
   This validates the CloudFormation stack can be deployed successfully.

2. Run health integration tests:
   ```bash
   make test-integration-health
   ```
   Validates infrastructure and basic health checks.

3. Run all integration tests including UI:
   ```bash
   make test-integration-all
   ```
   This runs the multi-user Playwright tests.

4. If any tests fail:
   - Review test output and screenshots
   - Fix issues
   - Re-run tests
   - Iterate until all tests pass

### Phase 6: Documentation & Cleanup

1. Update `README.md`:
   - Line 24: Update Jitsi version to `stable-10590`
   - Line 23: Update Ubuntu version to `24.04 LTS`
   - Add section on running integration tests

2. Update `CHANGELOG.md`:
   ```markdown
   ## [Unreleased]

   ### Changed
   - Upgraded Jitsi Meet from stable-9823 to stable-10590
   - Upgraded Ubuntu from 22.04 to 24.04 LTS
   - Upgraded devenv from 2.5.3 to 2.8.0
   - Upgraded oe-patterns-cdk-common from 4.1.4 to X.Y.Z

   ### Added
   - Integration test framework using pytest
   - Health and infrastructure tests
   - Multi-user UI workflow tests with Playwright
   - P2P to JVB mode transition test
   ```

3. Update `CLAUDE.md`:
   - Add section about integration tests
   - Document test make targets
   - Update version numbers

4. Commit changes to feature branch:
   ```bash
   git add .
   git commit -m "Upgrade Jitsi to stable-10590, Ubuntu 24.04, and add integration tests

   - Upgrade Jitsi Meet from stable-9823 to stable-10590
   - Upgrade Ubuntu from 22.04 to 24.04 LTS
   - Upgrade devenv from 2.5.3 to 2.8.0
   - Upgrade oe-patterns-cdk-common to latest
   - Add pytest-based integration test framework
   - Add multi-user workflow tests (P2P and JVB modes)
   - Add P2P to JVB transition test
   - Update documentation

   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   Co-Authored-By: Claude <noreply@anthropic.com>"
   ```

5. Push feature branch:
   ```bash
   git push -u origin feature/upgrade
   ```

## Key Design Decisions

### Why all-at-once upgrade?
All components (Jitsi, Ubuntu, devenv, oe-commons) are related to the runtime environment. Testing them together ensures compatibility and reduces the number of AMI build/test cycles.

### Why tagged releases for oe-patterns-cdk-common?
Tagged releases provide stability and predictability for production patterns. Feature branches are appropriate for development but not for marketplace products.

### Why manual verification before integration tests?
Manual verification allows the developer to understand how the upgraded Jitsi behaves before encoding that behavior into automated tests. It also catches issues early.

### Why test P2P → JVB transition?
This is a critical architectural feature of Jitsi. The transition from 2 to 3 participants switches from peer-to-peer to server-routed media. Testing this ensures both modes work and the transition is seamless.

## Risks & Mitigations

### Risk: Ubuntu 24.04 compatibility issues
**Mitigation:** The install scripts already support 24.04. The AMI build will fail early if there are package incompatibilities.

### Risk: Jitsi stable-10590 breaking changes
**Mitigation:** Manual verification phase allows catching functional issues before writing tests. Jitsi stable releases are generally backward compatible.

### Risk: Multi-user tests are flaky
**Mitigation:** Use proper wait conditions, timeouts, and retry logic. Playwright provides robust selectors and waiting mechanisms.

### Risk: oe-patterns-cdk-common upgrade breaks stack
**Mitigation:** Test `make synth` immediately after upgrade. If synthesis fails, we catch it before AMI building.

## Success Criteria

1. ✅ AMI builds successfully with Ubuntu 24.04 and Jitsi stable-10590
2. ✅ Stack deploys successfully to dev environment
3. ✅ Manual verification shows Jitsi works correctly
4. ✅ taskcat integration test passes
5. ✅ All health integration tests pass
6. ✅ Multi-user workflow tests pass (2-user, 3-user, transition)
7. ✅ Documentation is updated
8. ✅ Feature branch is committed and pushed

## Future Enhancements

- Add performance tests (latency, bandwidth usage)
- Add recording functionality tests
- Add screen sharing tests
- Add mobile browser compatibility tests
- Add load testing with 10+ participants
- Integrate tests into CI/CD pipeline
