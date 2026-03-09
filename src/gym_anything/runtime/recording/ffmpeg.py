from __future__ import annotations

import os
import shlex
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import IO, Optional

from ..runners.base import BaseRunner


@dataclass
class RecordingHandle:
    process: subprocess.Popen
    out_mp4: Path
    out_log: Path
    log_fp: Optional[IO[str]] = None


class FFmpegRecorder:
    """Attach FFmpeg to the runtime to record video/audio.

    For DockerRunner, it executes ffmpeg inside the container targeting the X11
    display (:99) and PulseAudio default monitor. It writes to a bind-mounted
    path under the episode artifacts directory.
    """

    def __init__(self, runner: BaseRunner):
        self.runner = runner

    def start(
        self,
        out_dir: Path,
        fps: int = 10,
        resolution: Optional[tuple[int, int]] = None,
        vcodec: str = "libx264",
        vcrf: int = 23,
        ar: int = 16000,
        ac: int = 1,
        acodec: str = "aac",
    ) -> RecordingHandle:
        out_dir = Path(out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

        out_mp4 = out_dir / "recording.mp4"
        out_log = out_dir / "ffmpeg.log"

        # Compose command executed inside the container. Ensure input options precede -i.
        container_out_dir = self.runner.to_container_path(out_dir)
        container_out_mp4 = Path(container_out_dir) / "recording.mp4"

        vid_size = f"-video_size {resolution[0]}x{resolution[1]}" if resolution else ""
        video_input = f"-f x11grab -framerate {fps} {vid_size} -i $DISPLAY"
        pulse_input = f"-f pulse -ac {ac} -ar {ar} -i default"

        log_fp: IO[str] = open(out_log, "w")

        def build_cmd(mode: str) -> str:
            """mode ∈ { 'pulse', 'anull', 'video' }"""
            parts = ["ffmpeg", "-y", "-loglevel", "warning", "-stats"]
            parts.extend(video_input.split())
            if mode == "pulse":
                parts.extend(pulse_input.split())
            elif mode == "anull":
                parts.extend(["-f", "lavfi", "-i", f"anullsrc=channel_layout={'mono' if ac == 1 else 'stereo'}:sample_rate={ar}"])
            parts.extend(["-c:v", vcodec, "-crf", str(int(vcrf)), "-pix_fmt", "yuv420p"])
            # Use fragmented MP4 to ensure file is playable even if ffmpeg is killed
            parts.extend(["-movflags", "+frag_keyframe+empty_moov"])
            if mode in {"pulse", "anull"}:
                parts.extend(["-c:a", acodec])
            parts.append(shlex.quote(str(container_out_mp4)))
            return " ".join(parts)

        def launch(cmd: str) -> subprocess.Popen:
            return self.runner.exec_async(cmd, stdout=log_fp, stderr=subprocess.STDOUT)

        # Try with audio first, then fallback to video-only if ffmpeg exits immediately
        proc = launch(build_cmd("pulse"))
        time.sleep(0.5)
        if proc.poll() is not None:
            # Try synthetic audio if requested, else video-only
            try_anullsrc = getattr(getattr(self.runner, 'spec', None), 'recording', None)
            try_anullsrc = bool(getattr(try_anullsrc, 'force_audio_track', False))
            if try_anullsrc:
                proc = launch(build_cmd("anull"))
                time.sleep(0.2)
            else:
                proc = launch(build_cmd("video"))
                time.sleep(0.2)

        return RecordingHandle(process=proc, out_mp4=out_mp4, out_log=out_log, log_fp=log_fp)

    def stop(self, handle: RecordingHandle) -> None:
        if handle.process.poll() is None:
            # Ask ffmpeg to terminate gracefully via SIGINT
            handle.process.terminate()
            try:
                handle.process.wait(timeout=5)
            except Exception:
                handle.process.kill()
        if handle.log_fp and not handle.log_fp.closed:
            try:
                handle.log_fp.close()
            except Exception:
                pass
