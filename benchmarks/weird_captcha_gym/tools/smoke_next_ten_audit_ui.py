#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from smoke_incubator_batch_one_ui import BENCH_ROOT, run_batch


MECHANICS = (
    "surreal_apple_on_tree_grid",
    "cursor_lens_reveal",
    "modifier_stack_image_grid",
    "board_game_captcha",
    "shadow_crime_lab",
    "craftcha_alchemy_bench",
    "occlusion_shell_swindle",
    "ribbon_switchboard",
    "magnetic_stripe_purgatory",
    "trajectory_catcher",
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Exercise the dashboard positions 17–26 principle audit cohort.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "next_ten_audit_v1"))
    parser.add_argument("--port", type=int, default=8925)
    parser.add_argument("--seed-prefix", default="next-ten-audit-canonical")
    args = parser.parse_args()
    run_batch(mechanics=MECHANICS, out_dir=Path(args.out_dir), port=args.port, seed_prefix=args.seed_prefix)


if __name__ == "__main__":
    main()
