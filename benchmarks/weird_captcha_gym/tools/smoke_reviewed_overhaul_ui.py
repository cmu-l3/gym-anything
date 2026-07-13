#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from benchmarks.weird_captcha_gym.tools.smoke_incubator_batch_one_ui import BENCH_ROOT, run_batch


MECHANICS = (
    "consequences_boss",
    "popup_exorcist",
    "slime_commute",
    "semantic_drag_drop_absurdity",
    "reload_interruption",
    "rotate_wrong_thing_upright",
    "bureaucratic_signature_trap",
    "wonky_text_hostile_rendering",
    "temporal_memory_first_change",
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Adversarially exercise the reviewed puzzle overhauls.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "reviewed_overhaul_v1"))
    parser.add_argument("--port", type=int, default=8940)
    parser.add_argument("--seed-prefix", default="reviewed-overhaul-smoke")
    args = parser.parse_args()
    run_batch(mechanics=MECHANICS, out_dir=Path(args.out_dir), port=args.port, seed_prefix=args.seed_prefix)


if __name__ == "__main__":
    main()
