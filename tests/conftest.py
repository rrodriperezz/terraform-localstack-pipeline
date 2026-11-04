import json
import subprocess
import sys
import time
from pathlib import Path

import boto3
import pytest

ROOT = Path(__file__).resolve().parents[1]

# The handler is deployed on its own, with no package around it, so in the zip it sits at
# the root and is imported as "handler". The tests import it the same way instead of
# turning src/ into a package, so they exercise the same module that runs in production
# and not a differently packaged variant.
sys.path.insert(0, str(ROOT / "src" / "processor"))

ENDPOINT = "http://localhost:4566"
REGION = "us-east-1"
CREDENTIALS = {"aws_access_key_id": "test", "aws_secret_access_key": "test"}


@pytest.fixture(scope="session")
def outputs():
    # Resource names are read from the state instead of being rebuilt by hand. If the
    # prefix or the environment changes, the tests still point at the right place.
    run = subprocess.run(
        ["terraform", f"-chdir={ROOT / 'terraform'}", "output", "-json"],
        capture_output=True,
        text=True,
        check=False,
    )

    if run.returncode != 0:
        pytest.fail(f"could not read the terraform outputs: {run.stderr.strip()}")

    raw = json.loads(run.stdout)

    if not raw:
        pytest.fail("the outputs are empty: run make apply before the tests")

    return {key: value["value"] for key, value in raw.items()}


def _client(service):
    return boto3.client(service, endpoint_url=ENDPOINT, region_name=REGION, **CREDENTIALS)


@pytest.fixture(scope="session")
def events():
    return _client("events")


@pytest.fixture(scope="session")
def sqs():
    return _client("sqs")


@pytest.fixture(scope="session")
def dynamodb():
    return boto3.resource("dynamodb", endpoint_url=ENDPOINT, region_name=REGION, **CREDENTIALS)


@pytest.fixture(scope="session")
def wait_until():
    # No fixed sleep, because timings vary by two orders of magnitude: the first function
    # invocation forces LocalStack to download and start the runtime image and can take
    # more than a minute, while the following ones answer in under a second. A sleep tuned
    # for the worst case would make the whole suite take minutes for nothing; a short one
    # makes it flaky.
    def _wait(condition, timeout=120, interval=2, description="the condition"):
        deadline = time.monotonic() + timeout

        while time.monotonic() < deadline:
            result = condition()

            if result:
                return result

            time.sleep(interval)

        pytest.fail(f"timed out after {timeout}s waiting for {description}")

    return _wait
