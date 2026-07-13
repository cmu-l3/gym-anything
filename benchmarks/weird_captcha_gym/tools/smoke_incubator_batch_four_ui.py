#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from smoke_incubator_batch_one_ui import BENCH_ROOT, run_batch


MECHANICS = (
    "microgame_gauntlet",
    "minecraft_block_grid",
    "relation_prompt_grounding",
    "rorschach_fixed_rubric",
    "single_scene_split_boxes",
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Exercise and capture historical Incubator Batch 4.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "incubator_batch_four_v1"))
    parser.add_argument("--port", type=int, default=8891)
    args = parser.parse_args()
    run_batch(mechanics=MECHANICS, out_dir=Path(args.out_dir), port=args.port, seed_prefix="incubator-batch-four-smoke")


if __name__ == "__main__":
    main()
