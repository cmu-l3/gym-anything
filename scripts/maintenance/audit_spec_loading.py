#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys

from gym_anything.verification import render_summary_text, verify_corpus


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Compatibility wrapper around gym_anything.verification.corpus checks. "
            "Prefer 'python -m gym_anything.cli verify corpus'."
        )
    )
    parser.add_argument(
        "root",
        nargs="?",
        default="benchmarks/environments",
        help="Root directory to scan (default: benchmarks/environments)",
    )
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    summary = verify_corpus(args.root)
    if args.json:
        print(json.dumps(summary.to_dict(), indent=2, sort_keys=True))
    else:
        print(render_summary_text(summary))
    return 0 if summary.ok else 1


if __name__ == "__main__":
    sys.exit(main())
