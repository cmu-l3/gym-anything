#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

from smoke_incubator_batch_one_ui import BENCH_ROOT, run_batch


MECHANICS = (
    "lidar_blacksite",
    "tomographic_baggage_surgery",
    "three_camera_claw_machine",
    "zero_g_cable_autopsy",
    "portal_freight_oversized_parcel",
)


def validate_viewport_pngs(out_dir: Path) -> None:
    pngs = sorted(out_dir.glob("*.png"))
    if not pngs:
        raise AssertionError(f"batch nine produced no PNG evidence in {out_dir}")
    wrong_size: list[str] = []
    for path in pngs:
        with Image.open(path) as image:
            if image.size != (1280, 720):
                wrong_size.append(f"{path.name}: {image.size[0]}x{image.size[1]}")
    if wrong_size:
        raise AssertionError(
            "batch nine evidence must be raw 1280x720 browser captures; "
            "fix the page layout instead of post-processing screenshots: "
            + ", ".join(wrong_size)
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Exercise and capture Interaction VI Batch 9.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "incubator_batch_nine_v1"))
    parser.add_argument("--port", type=int, default=8896)
    args = parser.parse_args()
    out_dir = Path(args.out_dir)
    run_batch(mechanics=MECHANICS, out_dir=out_dir, port=args.port, seed_prefix="incubator-batch-nine-smoke")
    validate_viewport_pngs(out_dir)


if __name__ == "__main__":
    main()
