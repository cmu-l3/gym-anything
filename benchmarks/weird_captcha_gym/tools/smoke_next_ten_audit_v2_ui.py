#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from smoke_incubator_batch_one_ui import BENCH_ROOT, run_batch


MECHANICS = (
    "impossible_panorama",
    "flat_pack_compliance",
    "crash_deadline_hovercar",
    "robot_art_critic",
    "wrong_number",
    "bomb_manual_from_hell",
    "dead_mans_switch",
    "blind_dice_courier",
    "input_lag_forklift",
    "insider_trading_captcha",
)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Exercise the dashboard positions 27–36 principle-audit cohort."
    )
    parser.add_argument(
        "--out-dir",
        default=str(BENCH_ROOT / "evidence" / "next_ten_audit_v2"),
    )
    parser.add_argument("--port", type=int, default=9080)
    parser.add_argument("--seed-prefix", default="next-ten-audit-v2-canonical")
    args = parser.parse_args()
    run_batch(
        mechanics=MECHANICS,
        out_dir=Path(args.out_dir),
        port=args.port,
        seed_prefix=args.seed_prefix,
    )


if __name__ == "__main__":
    main()
