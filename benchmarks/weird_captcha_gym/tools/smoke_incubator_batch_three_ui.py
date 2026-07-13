#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from smoke_incubator_batch_one_ui import BENCH_ROOT, run_batch


MECHANICS = (
    "code_to_diagram_captcha",
    "exit_vim_terminal_escape",
    "fake_desktop_automation_inversion",
    "impossible_ecology",
    "jigsaw_slider_alignment",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Exercise and capture historical Incubator Batch 3.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "incubator_batch_three_v1"))
    parser.add_argument("--port", type=int, default=8890)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    run_batch(
        mechanics=MECHANICS,
        out_dir=Path(args.out_dir),
        port=args.port,
        seed_prefix="incubator-batch-three-smoke",
    )


if __name__ == "__main__":
    main()
