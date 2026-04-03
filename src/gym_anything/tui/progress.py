"""Boot progress display for interactive mode.

Uses `rich` for a live-updating stage table with progress bar.
Falls back to plain print() on dumb terminals or piped output.
"""

from __future__ import annotations

import time
from collections import deque
from dataclasses import dataclass, field
from typing import List, Optional, Protocol, Tuple


# ---- Reporter protocol ----

class ProgressReporter(Protocol):
    """Interface for receiving boot progress events from runners."""

    def define_stages(self, stages: List[Tuple[str, str]]) -> None: ...
    def stage_start(self, key: str, detail: str = "") -> None: ...
    def stage_update(self, key: str, detail: str) -> None: ...
    def stage_done(self, key: str, detail: str = "") -> None: ...
    def stage_skip(self, key: str, reason: str = "") -> None: ...
    def stage_fail(self, key: str, error: str) -> None: ...
    def log(self, message: str) -> None: ...


# ---- Stage model ----

@dataclass
class _Stage:
    key: str
    label: str
    status: str = "pending"  # pending | running | done | skipped | failed
    detail: str = ""


# ---- Null reporter (no-op) ----

class NullReporter:
    """No-op reporter for non-interactive / programmatic usage."""

    def define_stages(self, stages): pass
    def stage_start(self, key, detail=""): pass
    def stage_update(self, key, detail): pass
    def stage_done(self, key, detail=""): pass
    def stage_skip(self, key, reason=""): pass
    def stage_fail(self, key, error): pass
    def log(self, message): pass
    def __enter__(self): return self
    def __exit__(self, *a): pass


# ---- Plain text reporter ----

class PrintReporter:
    """Plain-text fallback for dumb terminals / piped output."""

    def __init__(self):
        self._start_time = time.time()
        self._stages = {}
        self._total = 0
        self._done_count = 0

    def define_stages(self, stages: List[Tuple[str, str]]) -> None:
        self._stages = {key: label for key, label in stages}
        self._total = len(stages)
        self._done_count = 0

    def stage_start(self, key: str, detail: str = "") -> None:
        label = self._stages.get(key, key)
        suffix = f"  {detail}" if detail else ""
        print(f"  ...  {label}{suffix}", flush=True)

    def stage_update(self, key: str, detail: str) -> None:
        pass

    def stage_done(self, key: str, detail: str = "") -> None:
        label = self._stages.get(key, key)
        self._done_count += 1
        suffix = f"  {detail}" if detail else ""
        elapsed = time.time() - self._start_time
        print(f"  [{self._done_count}/{self._total}]  {label}{suffix}  ({elapsed:.0f}s)", flush=True)

    def stage_skip(self, key: str, reason: str = "") -> None:
        label = self._stages.get(key, key)
        self._done_count += 1
        suffix = f"  ({reason})" if reason else ""
        print(f"  skip {label}{suffix}", flush=True)

    def stage_fail(self, key: str, error: str) -> None:
        label = self._stages.get(key, key)
        print(f"  FAIL {label}  {error}", flush=True)

    def log(self, message: str) -> None:
        print(f"       {message}", flush=True)

    def __enter__(self): return self
    def __exit__(self, *a): pass


# ---- Rich TUI reporter ----

_MAX_LOG_LINES = 6


class RichBootProgress:
    """Live-updating boot progress display using rich."""

    def __init__(self, env_name: str = "", task_name: str = ""):
        from rich.console import Console
        self._console = Console()
        self._env_name = env_name
        self._task_name = task_name
        self._stages: List[_Stage] = []
        self._stage_map: dict[str, _Stage] = {}
        self._start_time = time.time()
        self._log_lines: deque = deque(maxlen=_MAX_LOG_LINES)
        self._live = None

    def define_stages(self, stages: List[Tuple[str, str]]) -> None:
        self._stages = [_Stage(key=k, label=l) for k, l in stages]
        self._stage_map = {s.key: s for s in self._stages}

    def stage_start(self, key: str, detail: str = "") -> None:
        stage = self._stage_map.get(key)
        if stage:
            stage.status = "running"
            stage.detail = detail
        self._refresh()

    def stage_update(self, key: str, detail: str) -> None:
        stage = self._stage_map.get(key)
        if stage:
            stage.detail = detail
        self._refresh()

    def stage_done(self, key: str, detail: str = "") -> None:
        stage = self._stage_map.get(key)
        if stage:
            stage.status = "done"
            if detail:
                stage.detail = detail
        self._refresh()

    def stage_skip(self, key: str, reason: str = "") -> None:
        stage = self._stage_map.get(key)
        if stage:
            stage.status = "skipped"
            stage.detail = reason
        self._refresh()

    def stage_fail(self, key: str, error: str) -> None:
        stage = self._stage_map.get(key)
        if stage:
            stage.status = "failed"
            stage.detail = error
        self._refresh()

    def log(self, message: str) -> None:
        """Add a log line to the scrolling log area inside the panel."""
        self._log_lines.append(message)
        self._refresh()

    def __rich_console__(self, console, options):
        """Called by Live on every auto-refresh — keeps timer updating."""
        yield self._render()

    def __enter__(self):
        from rich.live import Live
        self._start_time = time.time()
        self._live = Live(
            self,
            console=self._console,
            refresh_per_second=1,
            transient=True,
            redirect_stdout=True,
            redirect_stderr=True,
        )
        self._live.__enter__()
        return self

    def __exit__(self, *args):
        if self._live:
            self._live.__exit__(*args)
            self._live = None
        self._print_final_summary()

    def _refresh(self) -> None:
        if self._live:
            self._live.update(self)

    def _render(self):
        from rich.table import Table
        from rich.text import Text
        from rich.panel import Panel
        from rich.console import Group

        title = f"Booting: {self._env_name}"
        if self._task_name:
            title += f" (task: {self._task_name})"

        # Stage table
        table = Table(show_header=False, box=None, padding=(0, 1), expand=True)
        table.add_column(width=4, justify="right")
        table.add_column(ratio=1)
        table.add_column(ratio=1, style="dim")

        for stage in self._stages:
            if stage.status == "done":
                icon = Text("  \u2713", style="bold green")
                label = Text(stage.label)
                detail = Text(stage.detail, style="dim")
            elif stage.status == "running":
                icon = Text("  \u25cf", style="bold yellow")
                label = Text(stage.label, style="bold")
                detail = Text(stage.detail, style="yellow")
            elif stage.status == "failed":
                icon = Text("  \u2717", style="bold red")
                label = Text(stage.label, style="red")
                detail = Text(stage.detail, style="red")
            elif stage.status == "skipped":
                icon = Text("  -", style="dim")
                label = Text(stage.label, style="dim")
                detail = Text(stage.detail, style="dim")
            else:
                icon = Text("   ", style="dim")
                label = Text(stage.label, style="dim")
                detail = Text("")
            table.add_row(icon, label, detail)

        # Bottom bar: progress + elapsed
        done_count = sum(1 for s in self._stages if s.status in ("done", "skipped"))
        total = len(self._stages)
        elapsed = time.time() - self._start_time
        mins, secs = divmod(int(elapsed), 60)

        filled = int(30 * done_count / total) if total else 0
        bar = "\u2501" * filled + "\u2500" * (30 - filled)
        pct = f"{done_count/total*100:.0f}%" if total else "0%"
        bottom = Text(f"  [{done_count}/{total}] {bar} {pct}   {mins}m {secs:02d}s", style="dim")

        # Log lines (rendered inside panel, below stages)
        parts = [table, Text(""), bottom]
        if self._log_lines:
            parts.append(Text(""))
            for line in self._log_lines:
                parts.append(Text(f"  {line}", style="dim"))

        return Panel(
            Group(*parts),
            title=f"[bold]gym-anything[/bold]   {title}",
            border_style="blue",
            expand=True,
        )

    def _print_final_summary(self) -> None:
        elapsed = time.time() - self._start_time
        done = sum(1 for s in self._stages if s.status == "done")
        failed = sum(1 for s in self._stages if s.status == "failed")
        if failed:
            self._console.print(f"  [red]Boot failed[/red] ({done} stages done, {failed} failed) in {elapsed:.0f}s")
        else:
            self._console.print(f"  [green]Boot complete[/green] in {elapsed:.0f}s")


def create_reporter(env_name: str = "", task_name: str = "") -> RichBootProgress | PrintReporter:
    """Create the best available reporter for the current terminal."""
    try:
        from rich.console import Console
        c = Console()
        if c.is_terminal:
            return RichBootProgress(env_name=env_name, task_name=task_name)
    except ImportError:
        pass
    return PrintReporter()
