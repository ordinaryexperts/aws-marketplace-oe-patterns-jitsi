# Jitsi Integration Tests

Pytest + Playwright tests for the deployed Jitsi Meet pattern. Covers:

- Basic HTTP health (`test_health.py`)
- Multi-participant meetings via headless Chromium with fake media streams (`test_meetings.py`)

## Quickstart

From a machine that can reach your deployed Jitsi instance:

```bash
cd test/integration
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python -m playwright install chromium --with-deps

# Point at your deployed instance
export TEST_BASE_URL=https://jitsi-<you>.dev.patterns.ordinaryexperts.com
export TEST_STACK_NAME=oe-patterns-jitsi-<you>
export AWS_REGION=us-east-1

# Run everything
pytest

# Health checks only (no browser)
pytest --skip-ui

# Only the Playwright UI tests
pytest -m ui

# Only the heaviest 3-person test
pytest -m slow
```

## How the meeting tests work

Each "participant" is a separate Playwright browser context (isolated cookies/storage, shared Chromium process). The Chromium process launches with `--use-fake-ui-for-media-stream` and `--use-fake-device-for-media-stream`, so WebRTC gets fake cam/mic input and never prompts for permissions.

Tests navigate to `https://<host>/<RandomRoomName>#config.prejoinPageEnabled=false&userInfo.displayName="Alice"` to skip the prejoin page and set a display name.

After each participant joins, the test waits for `window.APP.conference.isJoined()` via JS evaluation, then checks `window.APP.conference.getParticipantCount()` and looks for at least one remote video track in the Redux store.

## Timing

- `test_health.py` — a few seconds.
- `test_two_person_meeting` — ~45-60 seconds.
- `test_three_person_meeting` — ~60-90 seconds.

Timing can fluctuate on first-run TURN/STUN negotiation. `config.join_wait_seconds` in `config.yaml` tunes the sleep between join and count-check.
