from __future__ import annotations

import shlex
from typing import Any, Dict, Optional

from .docker import DockerRunner


class BrowserRunner(DockerRunner):
    """Docker-backed runner specialized for a Chromium-based browser.

    It relies on Xvfb for display and xdotool for input. High-level actions are
    supported via `api_call`, e.g., `open_url` which focuses the address bar and
    types the URL (Ctrl+L, type, Return).
    """

    def _launch_entrypoint(self) -> None:
        # Ensure base entrypoint if provided (e.g., start_browser.sh)
        super()._launch_entrypoint()

    def _invoke_env_api(self, name: str, args: Dict[str, Any]) -> None:  # override
        # Handle simple browser-specific API calls; fallback to parent convention
        if name == "open_url":
            url = args.get("url")
            if not url:
                return
            # Focus address bar (Ctrl+L), type URL, press Return
            cmd = (
                "xdotool key ctrl+l && "
                + f"xdotool type --delay 1 {shlex.quote(str(url))} && "
                + "xdotool key Return"
            )
            self.exec(f"bash -lc {shlex.quote(cmd)}")
            return
        # Fallback to DockerRunner's env_api convention
        return super()._invoke_env_api(name, args)

