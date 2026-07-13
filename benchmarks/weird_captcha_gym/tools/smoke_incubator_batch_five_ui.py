#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from smoke_incubator_batch_one_ui import BENCH_ROOT, run_batch


MECHANICS = (
    "top_face_dice_arithmetic",
    "trace_shape_without_walls",
    "wizard_critter_capture",
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Exercise and capture historical Incubator Batch 5.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "incubator_batch_five_v1"))
    parser.add_argument("--port", type=int, default=8892)
    args = parser.parse_args()
    run_batch(mechanics=MECHANICS, out_dir=Path(args.out_dir), port=args.port, seed_prefix="incubator-batch-five-smoke")


if __name__ == "__main__":
    main()
