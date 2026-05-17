"""Recover lost expert-console session history from on-disk artifacts.

Invoke:

    gym-anything-extras research expert_console recover [--dry-run]

If `state/expert_console.sqlite3` is empty or missing, this command
reconstructs Session / Feedback / AgentRun / RunLog rows from:

  * each pipeline's `expert_feedback.md` (the source of truth for
    who submitted what, when, against which env/task);
  * `state/runs/*.log` (one file per dispatched run — env name,
    driver, and step markers are visible inside; birth/modify times
    bracket the run).

Reconstructed rows are titled `[recovered]` and marked ARCHIVED so
they don't look like live sessions.

The heavy lifting lives in `core.py` (regular package import); this
file is just the dispatcher entry point.
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path
from typing import Optional

from extras.research.expert_console.recover.core import apply, gather, print_plan
from extras.research.expert_console.server.config import Settings, get_settings
from extras.research.expert_console.server.db import reset_engine_for_tests


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gym-anything-extras research expert_console recover",
        description="Reconstruct expert-console session history from "
        "expert_feedback memory files + on-disk run logs.",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the plan without inserting rows.",
    )
    p.add_argument(
        "--db-path",
        default=None,
        help="Write to a different SQLite file (testing); defaults to "
        "the live state DB.",
    )
    return p


def run(argv: Optional[list[str]] = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = _build_parser().parse_args(argv or [])

    if args.db_path:
        settings = Settings(db_path=Path(args.db_path))
        reset_engine_for_tests(settings)
    else:
        settings = get_settings()

    plan = gather(settings)
    print_plan(plan)

    if args.dry_run:
        print("\n[dry-run] Not inserting.")
        return 0

    counts = apply(plan, settings)
    print()
    print(
        f"Inserted: {counts['sessions']} sessions, "
        f"{counts['feedbacks']} feedbacks, "
        f"{counts['runs']} runs, "
        f"{counts['run_logs']} run-log lines."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
