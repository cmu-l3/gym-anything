"""Post-boot interactive session display.

Shows connection info (VNC/SSH), elapsed uptime, and keyboard shortcuts.
"""

from __future__ import annotations

import os
import select
import subprocess
import sys
import termios
import time
import tty
from typing import Optional


def _open_vnc(port: int, password: str = "") -> None:
    """Open the VNC viewer for this platform."""
    url = f"vnc://localhost:{port}"
    if sys.platform == "darwin":
        subprocess.Popen(["open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif sys.platform == "linux":
        subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class InteractiveSession:
    """Post-boot interactive session with connection info and controls."""

    def __init__(self, env, *, auto_open_vnc: bool = False):
        self._env = env
        self._auto_open_vnc = auto_open_vnc
        self._start_time = time.time()

    def run(self) -> None:
        """Block until Ctrl+C. Shows connection panel, handles 'v' for VNC."""
        from rich.console import Console
        from rich.panel import Panel
        from rich.live import Live

        console = Console()
        session_info = self._env.get_session_info()

        vnc_port = session_info.vnc_port if session_info else None
        vnc_pw = session_info.vnc_password if session_info and session_info.vnc_password else "password"
        ssh_port = session_info.ssh_port if session_info else None
        ssh_user = session_info.ssh_user if session_info and session_info.ssh_user else "ga"
        ssh_pw = session_info.ssh_password if session_info and session_info.ssh_password else "password123"
        artifacts = self._env.episode_dir or ""

        if self._auto_open_vnc and vnc_port:
            _open_vnc(vnc_port, vnc_pw)

        def _build_panel() -> Panel:
            elapsed = time.time() - self._start_time
            mins, secs = divmod(int(elapsed), 60)

            lines = []
            if vnc_port:
                vnc_url = f"vnc://localhost:{vnc_port}"
                lines.append(f"  [bold]VNC[/bold]    {vnc_url}   password: {vnc_pw}")
            if ssh_port:
                lines.append(f"  [bold]SSH[/bold]    ssh -p {ssh_port} {ssh_user}@localhost   password: {ssh_pw}")
            if artifacts:
                lines.append(f"\n  Artifacts: [dim]{artifacts}[/dim]")
            lines.append(f"  Uptime: {mins}m {secs:02d}s")
            lines.append("")

            hints = []
            if vnc_port:
                hints.append("'v' open VNC")
            hints.append("Ctrl+C stop")
            lines.append(f"  [dim]{' | '.join(hints)}[/dim]")

            env_name = self._env.env_root or ""
            if hasattr(env_name, "name"):
                env_name = env_name.name

            return Panel(
                "\n".join(lines),
                title=f"[bold green]Environment Ready[/bold green] -- {env_name}",
                border_style="green",
                expand=True,
            )

        # Try raw terminal mode for keypress detection
        old_settings = None
        stdin_fd = None
        try:
            if sys.stdin.isatty():
                stdin_fd = sys.stdin.fileno()
                old_settings = termios.tcgetattr(stdin_fd)
                tty.setcbreak(stdin_fd)
        except Exception:
            pass

        try:
            with Live(_build_panel(), console=console, refresh_per_second=1, transient=False) as live:
                while True:
                    live.update(_build_panel())
                    # Check for keypress (non-blocking)
                    if stdin_fd is not None:
                        try:
                            r, _, _ = select.select([sys.stdin], [], [], 1.0)
                            if r:
                                ch = sys.stdin.read(1)
                                if ch == "v" and vnc_port:
                                    _open_vnc(vnc_port, vnc_pw)
                                    console.print("  [green]Opening VNC viewer...[/green]")
                        except Exception:
                            time.sleep(1)
                    else:
                        time.sleep(1)
        except KeyboardInterrupt:
            pass
        finally:
            # Restore terminal
            if old_settings is not None and stdin_fd is not None:
                termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_settings)

        console.print("\n  [yellow]Stopping environment...[/yellow]")
        self._env.close()
        console.print("  [green]Environment stopped.[/green]")
