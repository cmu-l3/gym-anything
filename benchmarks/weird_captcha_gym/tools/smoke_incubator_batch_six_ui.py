#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from smoke_incubator_batch_one_ui import BENCH_ROOT, run_batch


MECHANICS = (
    "shadow_crime_lab",
    "craftcha_alchemy_bench",
    "occlusion_shell_swindle",
    "ribbon_switchboard",
    "magnetic_stripe_purgatory",
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Exercise and capture Interaction III Batch 6.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "incubator_batch_six_v1"))
    parser.add_argument("--port", type=int, default=8893)
    args = parser.parse_args()
    run_batch(mechanics=MECHANICS, out_dir=Path(args.out_dir), port=args.port, seed_prefix="incubator-batch-six-smoke")


if __name__ == "__main__":
    main()
