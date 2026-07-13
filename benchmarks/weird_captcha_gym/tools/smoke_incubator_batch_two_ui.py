#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from smoke_incubator_batch_one_ui import BENCH_ROOT, run_batch


MECHANICS = (
    "insider_trading_captcha",
    "polyrhythm_customs",
    "exact_change_candy_cascade",
    "tiny_fps_customs",
    "thirty_year_time_wheel",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Exercise and capture Incubator Batch 2.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "incubator_batch_two_v1"))
    parser.add_argument("--port", type=int, default=8870)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    run_batch(
        mechanics=MECHANICS,
        out_dir=Path(args.out_dir),
        port=args.port,
        seed_prefix="incubator-batch-two-smoke",
    )


if __name__ == "__main__":
    main()
