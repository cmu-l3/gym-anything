#!/usr/bin/env python3
"""Seed Rocket.Chat with real release data from the official Rocket.Chat GitHub releases feed."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import requests


class RocketChatAPIError(RuntimeError):
    pass


class RocketChatClient:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip("/")
        self.session = requests.Session()

    def _url(self, path: str) -> str:
        return f"{self.base_url}{path}"

    def request(
        self,
        method: str,
        path: str,
        *,
        headers: Optional[Dict[str, str]] = None,
        payload: Optional[Dict[str, Any]] = None,
        timeout: int = 20,
        allow_error: bool = False,
    ) -> Dict[str, Any]:
        response = self.session.request(
            method,
            self._url(path),
            headers=headers,
            json=payload,
            timeout=timeout,
        )

        try:
            data = response.json()
        except json.JSONDecodeError as exc:
            raise RocketChatAPIError(f"Non-JSON response from {path}: HTTP {response.status_code}") from exc

        if response.status_code >= 400 and not allow_error:
            err = data.get("error") or data.get("message") or "unknown error"
            raise RocketChatAPIError(f"HTTP {response.status_code} from {path}: {err}")

        return data

    def wait_for_login(self, username: str, password: str, timeout_sec: int = 420) -> Tuple[str, str]:
        started = time.time()
        while time.time() - started < timeout_sec:
            try:
                data = self.request(
                    "POST",
                    "/api/v1/login",
                    payload={"user": username, "password": password},
                )
                token = data.get("data", {}).get("authToken")
                user_id = data.get("data", {}).get("userId")
                if token and user_id:
                    return token, user_id
            except Exception:
                pass

            time.sleep(5)

        raise RocketChatAPIError(
            f"Timed out waiting for successful login as '{username}' after {timeout_sec} seconds"
        )


def auth_headers(token: str, user_id: str) -> Dict[str, str]:
    return {
        "X-Auth-Token": token,
        "X-User-Id": user_id,
        "Content-Type": "application/json",
    }


def is_already_exists_error(resp: Dict[str, Any]) -> bool:
    error_text = (resp.get("error") or "").lower()
    error_type = (resp.get("errorType") or "").lower()
    return "already" in error_text or "already" in error_type or "duplicate" in error_type


def ensure_agent_user(
    client: RocketChatClient,
    headers: Dict[str, str],
    username: str,
    password: str,
    name: str,
    email: str,
) -> str:
    payload = {
        "username": username,
        "name": name,
        "email": email,
        "password": password,
        "verified": True,
        "roles": ["user"],
        "joinDefaultChannels": True,
        "requirePasswordChange": False,
        "sendWelcomeEmail": False,
    }

    resp = client.request(
        "POST",
        "/api/v1/users.create",
        headers=headers,
        payload=payload,
        allow_error=True,
    )

    if resp.get("success"):
        return resp.get("user", {}).get("_id", "")

    if is_already_exists_error(resp):
        info = client.request(
            "GET",
            f"/api/v1/users.info?username={username}",
            headers=headers,
        )
        return info.get("user", {}).get("_id", "")

    raise RocketChatAPIError(f"Could not create agent user: {resp}")


def ensure_channel(
    client: RocketChatClient,
    headers: Dict[str, str],
    channel_name: str,
    agent_username: str,
) -> str:
    create_payload = {
        "name": channel_name,
        "members": [agent_username],
        "readOnly": False,
    }
    resp = client.request(
        "POST",
        "/api/v1/channels.create",
        headers=headers,
        payload=create_payload,
        allow_error=True,
    )

    if resp.get("success"):
        channel_id = resp.get("channel", {}).get("_id", "")
    elif is_already_exists_error(resp):
        info = client.request(
            "GET",
            f"/api/v1/channels.info?roomName={channel_name}",
            headers=headers,
        )
        channel_id = info.get("channel", {}).get("_id", "")
    else:
        raise RocketChatAPIError(f"Could not create/get channel '{channel_name}': {resp}")

    invite_payload = {"roomName": channel_name, "username": agent_username}
    invite_resp = client.request(
        "POST",
        "/api/v1/channels.invite",
        headers=headers,
        payload=invite_payload,
        allow_error=True,
    )
    if not invite_resp.get("success") and not is_already_exists_error(invite_resp):
        raise RocketChatAPIError(f"Could not invite '{agent_username}' to '{channel_name}': {invite_resp}")

    return channel_id


def load_releases(path: Path) -> List[Dict[str, Any]]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, list):
        raise RocketChatAPIError(f"Expected list in release data file: {path}")

    filtered: List[Dict[str, Any]] = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        if entry.get("draft") or entry.get("prerelease"):
            continue

        if not entry.get("tag_name") or not entry.get("published_at") or not entry.get("html_url"):
            continue

        filtered.append(
            {
                "tag_name": str(entry.get("tag_name")),
                "name": str(entry.get("name") or entry.get("tag_name")),
                "published_at": str(entry.get("published_at")),
                "html_url": str(entry.get("html_url")),
            }
        )

    filtered.sort(key=lambda x: x["published_at"], reverse=True)
    return filtered


def post_release_messages(
    client: RocketChatClient,
    headers: Dict[str, str],
    channel_name: str,
    releases: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    posted: List[Dict[str, Any]] = []

    for rel in reversed(releases):
        date_only = rel["published_at"].split("T", 1)[0]
        text = (
            f"Official Rocket.Chat release {rel['name']} ({rel['tag_name']}) "
            f"published on {date_only}. Source: {rel['html_url']}"
        )
        payload = {
            "channel": f"#{channel_name}",
            "text": text,
        }
        resp = client.request("POST", "/api/v1/chat.postMessage", headers=headers, payload=payload)

        if not resp.get("success"):
            raise RocketChatAPIError(f"Failed posting release message for {rel['tag_name']}: {resp}")

        posted.append(
            {
                "tag_name": rel["tag_name"],
                "name": rel["name"],
                "published_at": rel["published_at"],
                "html_url": rel["html_url"],
                "message_id": resp.get("message", {}).get("_id", ""),
            }
        )

    return posted


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--admin-username", required=True)
    parser.add_argument("--admin-password", required=True)
    parser.add_argument("--agent-username", required=True)
    parser.add_argument("--agent-password", required=True)
    parser.add_argument("--agent-name", required=True)
    parser.add_argument("--agent-email", required=True)
    parser.add_argument("--channel-name", required=True)
    parser.add_argument("--release-data", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    release_path = Path(args.release_data)
    if not release_path.exists():
        raise RocketChatAPIError(f"Release data file does not exist: {release_path}")

    releases = load_releases(release_path)
    if len(releases) < 8:
        raise RocketChatAPIError(
            f"Need at least 8 stable releases in source data, found {len(releases)}"
        )

    selected_releases = releases[:12]

    client = RocketChatClient(args.base_url)
    admin_token, admin_user_id = client.wait_for_login(args.admin_username, args.admin_password)
    admin_headers = auth_headers(admin_token, admin_user_id)

    agent_user_id = ensure_agent_user(
        client,
        admin_headers,
        args.agent_username,
        args.agent_password,
        args.agent_name,
        args.agent_email,
    )

    channel_id = ensure_channel(client, admin_headers, args.channel_name, args.agent_username)

    posted = post_release_messages(client, admin_headers, args.channel_name, selected_releases)

    target_release = selected_releases[0]
    manifest = {
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source": {
            "type": "github_api_snapshot",
            "url": "https://api.github.com/repos/RocketChat/Rocket.Chat/releases?per_page=25",
            "local_file": str(release_path),
        },
        "workspace": {
            "base_url": args.base_url,
            "admin_username": args.admin_username,
            "agent_username": args.agent_username,
            "agent_user_id": agent_user_id,
            "channel_name": args.channel_name,
            "channel_id": channel_id,
        },
        "target_release": target_release,
        "seeded_releases": posted,
        "seeded_message_count": len(posted),
    }

    out_path = Path(args.output)
    out_path.write_text(json.dumps(manifest, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")

    print(json.dumps({
        "status": "ok",
        "channel": args.channel_name,
        "seeded_message_count": len(posted),
        "target_release": target_release,
    }, ensure_ascii=True))

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
