"""
Level 1: Basic HTTP/TLS/CloudFormation checks for Jitsi.
Fast, no browser.
"""

import ssl
import socket
from urllib.parse import urlparse

import pytest
import requests


class TestJitsiHealth:

    def test_https_accessible(self, base_url):
        r = requests.get(base_url, timeout=30, allow_redirects=True)
        assert r.status_code == 200, f"Failed to access {base_url}: {r.status_code}"
        assert r.url.startswith("https://"), "Jitsi must be served over HTTPS"

    def test_response_time(self, base_url):
        import time
        start = time.time()
        r = requests.get(base_url, timeout=30)
        elapsed = time.time() - start
        assert r.status_code == 200
        assert elapsed < 10.0, f"Response time {elapsed:.2f}s exceeds 10s"

    def test_ssl_certificate(self, base_url):
        parsed = urlparse(base_url)
        with socket.create_connection((parsed.hostname, parsed.port or 443), timeout=10) as sock:
            with ssl.create_default_context().wrap_socket(sock, server_hostname=parsed.hostname) as ssock:
                assert ssock.getpeercert() is not None

    def test_config_js_served(self, base_url):
        """Jitsi's config.js should be served — confirms web container is up."""
        r = requests.get(f"{base_url}/config.js", timeout=10)
        assert r.status_code == 200
        assert "var config" in r.text, "config.js should contain Jitsi config"


class TestJitsiInfrastructure:

    def test_cloudformation_stack_exists(self, cloudformation_client, stack_name):
        response = cloudformation_client.describe_stacks(StackName=stack_name)
        assert len(response["Stacks"]) == 1
        stack = response["Stacks"][0]
        assert stack["StackStatus"] in ["CREATE_COMPLETE", "UPDATE_COMPLETE"], \
            f"Stack in unexpected state: {stack['StackStatus']}"

    def test_stack_outputs(self, stack_outputs):
        for required in ["DnsSiteUrlOutput"]:
            assert required in stack_outputs, f"Missing output: {required}"
            assert stack_outputs[required], f"Output {required} is empty"
