#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from smoke_incubator_batch_one_ui import BENCH_ROOT, run_batch


MECHANICS = (
    "photograph_eats_the_room",
    "clockwork_doppelganger_customs",
    "recursive_dollhouse_smuggling",
    "flat_prisoner",
    "forced_perspective_moving_day",
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Exercise and capture Interaction V Batch 8.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "incubator_batch_eight_v1"))
    parser.add_argument("--port", type=int, default=8895)
    args = parser.parse_args()
    run_batch(mechanics=MECHANICS, out_dir=Path(args.out_dir), port=args.port, seed_prefix="incubator-batch-eight-smoke")


if __name__ == "__main__":
    main()
