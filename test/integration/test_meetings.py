"""
Level 3: Multi-participant meeting tests using Playwright.

Validates that N participants can join the same Jitsi room and each
observes the expected participant count. Uses Chromium's fake media
stream flags so no real camera/mic is required.

Requires:
  python -m playwright install chromium

Usage:
  pytest test_meetings.py            # run all
  pytest test_meetings.py -m ui      # only Playwright tests
  pytest test_meetings.py -m slow    # only 3-person test
"""

import random
import string
import time
import urllib.parse
from contextlib import contextmanager

import pytest
from playwright.sync_api import sync_playwright


def _random_room_name() -> str:
    """Random alphabetic room name so tests don't collide."""
    return "OEPatternsTest" + "".join(random.choices(string.ascii_letters, k=10))


def _join_url(base_url: str, room: str) -> str:
    """Build a Jitsi join URL. Modern Jitsi (post-2022) ignores URL-hash
    config overrides for prejoin, so we interact with the prejoin UI instead.
    """
    hash_params = "&".join([
        "config.disableDeepLinking=true",
    ])
    return f"{base_url}/{room}#{hash_params}"


@contextmanager
def _chromium_browser():
    """Chromium with fake media streams so WebRTC doesn't prompt for cam/mic."""
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=[
                "--use-fake-ui-for-media-stream",
                "--use-fake-device-for-media-stream",
                "--autoplay-policy=no-user-gesture-required",
                "--disable-dev-shm-usage",
            ],
        )
        try:
            yield browser
        finally:
            browser.close()


def _open_participant(browser, base_url: str, room: str, display_name: str, join_wait: int):
    """Open a new browser context (= new participant), join the room, wait for WebRTC.

    Handles the prejoin page by filling in display name + clicking "Join meeting".
    Returns (context, page). Caller closes the context.
    """
    ctx = browser.new_context(
        viewport={"width": 1280, "height": 720},
        permissions=["camera", "microphone"],
    )
    page = ctx.new_page()
    url = _join_url(base_url, room)
    page.goto(url, wait_until="domcontentloaded", timeout=60000)

    # Prejoin page: fill in display name + click Join
    # Selectors are tolerant to minor Jitsi UI changes.
    try:
        name_input = page.wait_for_selector(
            'input[placeholder*="name" i], input[aria-label*="name" i]',
            timeout=15000,
        )
        name_input.fill(display_name)
        # "Join meeting" button has this visible text
        page.get_by_role("button", name="Join meeting").first.click(timeout=5000)
    except Exception:
        # Some configs / future versions may skip prejoin entirely — that's fine.
        pass

    # Wait for conference join
    page.wait_for_function(
        "() => typeof window.APP !== 'undefined' && window.APP.conference && window.APP.conference.isJoined()",
        timeout=60000,
    )
    # Give WebRTC a moment to negotiate media
    time.sleep(join_wait)
    return ctx, page


def _participant_count(page) -> int:
    """Count of participants including local user, per Jitsi's Redux store.

    Older Jitsi exposed APP.conference.getParticipantCount() but modern
    versions have removed it. The Redux store `features/base/participants`
    slice holds `local` (the local participant) and `remote` (a JS Map of
    remote participants). Total is 1 + remote.size.
    """
    return page.evaluate(
        """() => {
            const s = window.APP.store.getState()['features/base/participants'];
            return 1 + (s.remote?.size ?? 0);
        }"""
    )


def _remote_tracks_present(page) -> bool:
    """Returns True if the local peer has at least one remote video track."""
    return page.evaluate(
        """
        () => {
            try {
                const tracks = window.APP.store
                    .getState()['features/base/tracks']
                    .filter(t => t.mediaType === 'video' && !t.local);
                return tracks.length > 0;
            } catch (e) {
                return false;
            }
        }
        """
    )


@pytest.mark.ui
class TestTwoPersonMeeting:
    """2 participants join the same room and confirm they see each other."""

    def test_two_person_meeting(self, base_url, config):
        room = _random_room_name()
        join_wait = config["test"].get("join_wait_seconds", 15)

        with _chromium_browser() as browser:
            ctx_a, page_a = _open_participant(browser, base_url, room, "Alice", join_wait)
            try:
                ctx_b, page_b = _open_participant(browser, base_url, room, "Bob", join_wait)
                try:
                    # Give remote negotiation a moment
                    time.sleep(5)

                    count_a = _participant_count(page_a)
                    count_b = _participant_count(page_b)
                    assert count_a == 2, f"Alice sees {count_a} participants, expected 2"
                    assert count_b == 2, f"Bob sees {count_b} participants, expected 2"

                    # Each peer should see at least one remote video track
                    assert _remote_tracks_present(page_a), "Alice has no remote video tracks"
                    assert _remote_tracks_present(page_b), "Bob has no remote video tracks"
                finally:
                    ctx_b.close()
            finally:
                ctx_a.close()


@pytest.mark.ui
@pytest.mark.slow
class TestThreePersonMeeting:
    """3 participants join the same room and confirm all see each other."""

    def test_three_person_meeting(self, base_url, config):
        room = _random_room_name()
        join_wait = config["test"].get("join_wait_seconds", 15)

        contexts = []
        pages = []
        with _chromium_browser() as browser:
            try:
                for name in ("Alice", "Bob", "Carol"):
                    ctx, page = _open_participant(browser, base_url, room, name, join_wait)
                    contexts.append(ctx)
                    pages.append(page)

                # Give the whole room time to negotiate
                time.sleep(10)

                for i, (name, page) in enumerate(zip(("Alice", "Bob", "Carol"), pages)):
                    count = _participant_count(page)
                    assert count == 3, f"{name} sees {count} participants, expected 3"
                    assert _remote_tracks_present(page), f"{name} has no remote video tracks"
            finally:
                for ctx in contexts:
                    try:
                        ctx.close()
                    except Exception:
                        pass
