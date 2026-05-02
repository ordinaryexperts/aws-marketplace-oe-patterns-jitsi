"""
Pytest configuration and shared fixtures for Jitsi integration tests.
"""

import os
import yaml
import pytest
import boto3
from pathlib import Path


def pytest_addoption(parser):
    parser.addoption("--base-url", action="store", default=None)
    parser.addoption("--stack-name", action="store", default=None)
    parser.addoption("--skip-ui", action="store_true", default=False)


@pytest.fixture(scope="session")
def config():
    config_path = Path(__file__).parent / "config.yaml"
    with open(config_path) as f:
        return yaml.safe_load(f)


@pytest.fixture(scope="session")
def base_url(request, config):
    url = (
        request.config.getoption("--base-url")
        or os.environ.get("TEST_BASE_URL")
        or config["urls"]["base_url"]
    )
    return url.rstrip("/")


@pytest.fixture(scope="session")
def stack_name(request, config):
    return (
        request.config.getoption("--stack-name")
        or os.environ.get("TEST_STACK_NAME")
        or config["aws"]["stack_name"]
    )


@pytest.fixture(scope="session")
def aws_region(config):
    return os.environ.get("AWS_REGION") or config["aws"]["region"]


@pytest.fixture(scope="session")
def cloudformation_client(aws_region):
    return boto3.client("cloudformation", region_name=aws_region)


@pytest.fixture(scope="session")
def stack_outputs(cloudformation_client, stack_name):
    try:
        response = cloudformation_client.describe_stacks(StackName=stack_name)
        stack = response["Stacks"][0]
        return {o["OutputKey"]: o["OutputValue"] for o in stack.get("Outputs", [])}
    except Exception as e:
        pytest.fail(f"Failed to get stack outputs: {e}")


def pytest_collection_modifyitems(config, items):
    skip_ui = config.getoption("--skip-ui")
    if skip_ui:
        marker = pytest.mark.skip(reason="--skip-ui option provided")
        for item in items:
            if "ui" in item.keywords:
                item.add_marker(marker)
