#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from smoke_incubator_batch_one_ui import BENCH_ROOT, run_batch


MECHANICS = (
    "trajectory_catcher",
    "impossible_panorama",
    "flat_pack_compliance",
    "crash_deadline_hovercar",
    "robot_art_critic",
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Exercise and capture Interaction IV Batch 7.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "incubator_batch_seven_v1"))
    parser.add_argument("--port", type=int, default=8894)
    args = parser.parse_args()
    run_batch(mechanics=MECHANICS, out_dir=Path(args.out_dir), port=args.port, seed_prefix="incubator-batch-seven-smoke")


if __name__ == "__main__":
    main()
