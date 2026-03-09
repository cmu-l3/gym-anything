from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from typing import Optional


def assemble_step_video(
    episode_dir: Path,
    *,
    fps: int = 10,
    vcodec: str = "libx264",
    vcrf: int = 23,
    output_name: str = "recording.mp4",
) -> Optional[Path]:
    """Assemble a video from per-step screenshots if FFmpeg is available."""
    episode_dir = Path(episode_dir)
    frames = sorted(episode_dir.glob("frame_*.png"))
    if not frames:
        return None

    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return None

    out_path = episode_dir / output_name
    pattern = episode_dir / "frame_%05d.png"
    cmd = [
        ffmpeg,
        "-y",
        "-loglevel",
        "warning",
        "-framerate",
        str(int(fps)),
        "-i",
        str(pattern),
        "-vf",
        "pad=ceil(iw/2)*2:ceil(ih/2)*2",
        "-c:v",
        vcodec,
        "-crf",
        str(int(vcrf)),
        "-pix_fmt",
        "yuv420p",
        str(out_path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return None
    if not out_path.exists():
        return None
    return out_path


__all__ = ["assemble_step_video"]
