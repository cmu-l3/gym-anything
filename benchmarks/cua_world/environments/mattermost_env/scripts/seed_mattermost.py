#!/usr/bin/env python3
"""Seed Mattermost with real release data from the official Mattermost GitHub releases feed."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import requests


class MattermostAPIError(RuntimeError):
    pass


class MattermostClient:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip("/")
        self.session = requests.Session()
        self.token: Optional[str] = None

    def _url(self, path: str) -> str:
        return f"{self.base_url}{path}"

    def _headers(self) -> Dict[str, str]:
        h = {"Content-Type": "application/json"}
        if self.token:
            h["Authorization"] = f"Bearer {self.token}"
        return h

    def request(
        self,
        method: str,
        path: str,
        *,
        payload: Optional[Dict[str, Any]] = None,
        timeout: int = 20,
        allow_error: bool = False,
    ) -> Tuple[int, Any]:
        response = self.session.request(
            method,
            self._url(path),
            headers=self._headers(),
            json=payload,
            timeout=timeout,
        )

        try:
            data = response.json()
        except (json.JSONDecodeError, ValueError):
            if response.status_code >= 400 and not allow_error:
                raise MattermostAPIError(
                    f"Non-JSON response from {path}: HTTP {response.status_code}"
                )
            data = {}

        if response.status_code >= 400 and not allow_error:
            msg = ""
            if isinstance(data, dict):
                msg = data.get("message") or data.get("detailed_error") or str(data)
            raise MattermostAPIError(f"HTTP {response.status_code} from {path}: {msg}")

        return response.status_code, data

    def wait_for_server(self, timeout_sec: int = 300) -> None:
        """Wait for Mattermost server to be reachable."""
        started = time.time()
        while time.time() - started < timeout_sec:
            try:
                status, _ = self.request("GET", "/api/v4/system/ping", allow_error=True)
                if status == 200:
                    return
            except Exception:
                pass
            time.sleep(5)
        raise MattermostAPIError(f"Server not reachable after {timeout_sec}s")

    def create_admin_user(self, username: str, password: str, email: str) -> str:
        """Create the initial admin user via the API."""
        payload = {
            "email": email,
            "username": username,
            "password": password,
        }
        status, data = self.request(
            "POST", "/api/v4/users", payload=payload, allow_error=True
        )
        if status in (200, 201):
            user_id = data.get("id", "")
            print(f"Created admin user: {username} (id={user_id})")
            return user_id
        elif status == 400 and "already" in str(data).lower():
            print(f"Admin user {username} already exists, logging in...")
            return ""
        else:
            # Might fail if server already initialized; try login instead
            print(f"Admin user creation returned {status}: {data}")
            return ""

    def login(self, username: str, password: str) -> str:
        """Login and store auth token. Returns user_id."""
        started = time.time()
        last_err = None
        while time.time() - started < 120:
            try:
                status, data = self.request(
                    "POST",
                    "/api/v4/users/login",
                    payload={"login_id": username, "password": password},
                    allow_error=True,
                )
                if status == 200:
                    self.token = data.get("id", None)
                    # Token is in the response header
                    # Actually Mattermost returns the token in the Token header
                    resp = self.session.post(
                        self._url("/api/v4/users/login"),
                        json={"login_id": username, "password": password},
                        timeout=20,
                    )
                    if resp.status_code == 200:
                        self.token = resp.headers.get("Token", "")
                        user_data = resp.json()
                        return user_data.get("id", "")
                elif status == 401:
                    raise MattermostAPIError(f"Login failed for {username}: invalid credentials")
            except MattermostAPIError:
                raise
            except Exception as e:
                last_err = e

            time.sleep(3)

        raise MattermostAPIError(f"Login timed out for {username}: {last_err}")

    def create_user(self, username: str, password: str, email: str) -> str:
        """Create a regular user."""
        payload = {
            "email": email,
            "username": username,
            "password": password,
        }
        status, data = self.request(
            "POST", "/api/v4/users", payload=payload, allow_error=True
        )
        if status in (200, 201):
            return data.get("id", "")
        elif "already" in str(data).lower() or status == 400:
            # User already exists, get their ID
            status2, data2 = self.request(
                "GET", f"/api/v4/users/username/{username}", allow_error=True
            )
            if status2 == 200:
                return data2.get("id", "")
        raise MattermostAPIError(f"Could not create user {username}: {status} {data}")

    def create_team(self, name: str, display_name: str) -> str:
        """Create a team."""
        payload = {
            "name": name,
            "display_name": display_name,
            "type": "O",  # Open team
        }
        status, data = self.request(
            "POST", "/api/v4/teams", payload=payload, allow_error=True
        )
        if status in (200, 201):
            return data.get("id", "")
        elif "already" in str(data).lower() or status == 400:
            # Team exists, get ID by name
            status2, data2 = self.request(
                "GET", f"/api/v4/teams/name/{name}", allow_error=True
            )
            if status2 == 200:
                return data2.get("id", "")
        raise MattermostAPIError(f"Could not create team {name}: {status} {data}")

    def add_user_to_team(self, team_id: str, user_id: str) -> None:
        """Add a user to a team."""
        payload = {"team_id": team_id, "user_id": user_id}
        self.request(
            "POST", f"/api/v4/teams/{team_id}/members", payload=payload, allow_error=True
        )

    def create_channel(self, team_id: str, name: str, display_name: str, purpose: str = "") -> str:
        """Create a public channel."""
        payload = {
            "team_id": team_id,
            "name": name,
            "display_name": display_name,
            "type": "O",
            "purpose": purpose,
        }
        status, data = self.request(
            "POST", "/api/v4/channels", payload=payload, allow_error=True
        )
        if status in (200, 201):
            return data.get("id", "")
        elif "already" in str(data).lower() or status == 400:
            status2, data2 = self.request(
                "GET",
                f"/api/v4/teams/{team_id}/channels/name/{name}",
                allow_error=True,
            )
            if status2 == 200:
                return data2.get("id", "")
        raise MattermostAPIError(f"Could not create channel {name}: {status} {data}")

    def add_user_to_channel(self, channel_id: str, user_id: str) -> None:
        """Add a user to a channel."""
        payload = {"user_id": user_id}
        self.request(
            "POST",
            f"/api/v4/channels/{channel_id}/members",
            payload=payload,
            allow_error=True,
        )

    def post_message(self, channel_id: str, message: str) -> str:
        """Post a message to a channel. Returns post_id."""
        payload = {"channel_id": channel_id, "message": message}
        status, data = self.request("POST", "/api/v4/posts", payload=payload)
        return data.get("id", "")

    def get_team_channels(self, team_id: str) -> List[Dict[str, Any]]:
        """Get all public channels for a team."""
        status, data = self.request(
            "GET", f"/api/v4/teams/{team_id}/channels", allow_error=True
        )
        if status == 200 and isinstance(data, list):
            return data
        return []


def load_releases(path: Path) -> List[Dict[str, Any]]:
    """Load and filter release data from JSON file."""
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, list):
        raise MattermostAPIError(f"Expected list in release data file: {path}")

    filtered: List[Dict[str, Any]] = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        if not entry.get("tag_name") or not entry.get("published_at"):
            continue

        filtered.append(
            {
                "tag_name": str(entry["tag_name"]),
                "name": str(entry.get("name") or entry["tag_name"]),
                "published_at": str(entry["published_at"]),
                "html_url": str(entry.get("html_url", "")),
            }
        )

    filtered.sort(key=lambda x: x["published_at"], reverse=True)
    return filtered


def post_release_messages(
    client: MattermostClient,
    channel_id: str,
    releases: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """Post release announcement messages to the channel."""
    posted: List[Dict[str, Any]] = []

    for rel in reversed(releases):
        date_only = rel["published_at"].split("T", 1)[0]
        text = (
            f"**Mattermost Release {rel['name']}** ({rel['tag_name']})\n"
            f"Published: {date_only}\n"
            f"Release notes: {rel['html_url']}"
        )
        post_id = client.post_message(channel_id, text)

        posted.append(
            {
                "tag_name": rel["tag_name"],
                "name": rel["name"],
                "published_at": rel["published_at"],
                "html_url": rel["html_url"],
                "post_id": post_id,
            }
        )

    return posted


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--admin-username", required=True)
    parser.add_argument("--admin-password", required=True)
    parser.add_argument("--admin-email", required=True)
    parser.add_argument("--agent-username", required=True)
    parser.add_argument("--agent-password", required=True)
    parser.add_argument("--agent-email", required=True)
    parser.add_argument("--team-name", required=True)
    parser.add_argument("--channel-name", required=True)
    parser.add_argument("--release-data", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    release_path = Path(args.release_data)
    if not release_path.exists():
        raise MattermostAPIError(f"Release data file does not exist: {release_path}")

    releases = load_releases(release_path)
    if len(releases) < 5:
        raise MattermostAPIError(
            f"Need at least 5 stable releases in source data, found {len(releases)}"
        )

    selected_releases = releases[:15]

    client = MattermostClient(args.base_url)
    client.wait_for_server()

    # Create admin user (first user on fresh install becomes admin)
    client.create_admin_user(args.admin_username, args.admin_password, args.admin_email)

    # Login as admin
    admin_user_id = client.login(args.admin_username, args.admin_password)
    print(f"Logged in as admin: {admin_user_id}")

    # Create team
    team_id = client.create_team(args.team_name, "Main Team")
    print(f"Team created/found: {team_id}")

    # Add admin to team
    client.add_user_to_team(team_id, admin_user_id)

    # Create agent user
    agent_user_id = client.create_user(
        args.agent_username, args.agent_password, args.agent_email
    )
    print(f"Agent user created/found: {agent_user_id}")

    # Add agent to team
    client.add_user_to_team(team_id, agent_user_id)

    # Create release-updates channel
    channel_id = client.create_channel(
        team_id,
        args.channel_name,
        "Release Updates",
        purpose="Official Mattermost release announcements from GitHub",
    )
    print(f"Channel created/found: {channel_id}")

    # Add both users to channel
    client.add_user_to_channel(channel_id, admin_user_id)
    client.add_user_to_channel(channel_id, agent_user_id)

    # Create additional channels for variety
    extra_channels = [
        ("general-discussion", "General Discussion", "General team discussions"),
        ("engineering", "Engineering", "Engineering team coordination"),
        ("devops", "DevOps", "Infrastructure and deployment discussions"),
    ]
    extra_channel_ids = {}
    for ch_name, ch_display, ch_purpose in extra_channels:
        ch_id = client.create_channel(team_id, ch_name, ch_display, purpose=ch_purpose)
        extra_channel_ids[ch_name] = ch_id
        client.add_user_to_channel(ch_id, admin_user_id)
        client.add_user_to_channel(ch_id, agent_user_id)

    # Post release messages
    posted = post_release_messages(client, channel_id, selected_releases)

    # Post some messages in other channels for realism
    client.post_message(
        extra_channel_ids.get("engineering", channel_id),
        "Team standup reminder: Please post your daily updates in this channel by 10 AM.",
    )
    client.post_message(
        extra_channel_ids.get("devops", channel_id),
        "Deployment pipeline updated. All services now use the new CI/CD workflow.",
    )
    client.post_message(
        extra_channel_ids.get("general-discussion", channel_id),
        "Welcome to the team workspace! Please introduce yourselves here.",
    )

    target_release = selected_releases[0]
    manifest = {
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source": {
            "type": "github_api_snapshot",
            "url": "https://api.github.com/repos/mattermost/mattermost/releases?per_page=30",
            "local_file": str(release_path),
        },
        "workspace": {
            "base_url": args.base_url,
            "admin_username": args.admin_username,
            "admin_user_id": admin_user_id,
            "agent_username": args.agent_username,
            "agent_user_id": agent_user_id,
            "team_name": args.team_name,
            "team_id": team_id,
            "channel_name": args.channel_name,
            "channel_id": channel_id,
            "extra_channels": extra_channel_ids,
        },
        "target_release": target_release,
        "seeded_releases": posted,
        "seeded_message_count": len(posted),
    }

    out_path = Path(args.output)
    out_path.write_text(
        json.dumps(manifest, ensure_ascii=True, indent=2) + "\n", encoding="utf-8"
    )

    print(
        json.dumps(
            {
                "status": "ok",
                "team": args.team_name,
                "channel": args.channel_name,
                "seeded_message_count": len(posted),
                "target_release": target_release,
            },
            ensure_ascii=True,
        )
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
