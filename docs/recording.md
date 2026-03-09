# Recording And Observations

There are two related but different data paths in the current runtime:

- per-step observations
- continuous FFmpeg episode recording

## Per-Step Observations

`GymAnythingEnv.capture_observation()` currently builds observations from configured modalities.

### `rgb_screen`

Per step, the environment writes:

- `frame_00000.png`
- `frame_00001.png`
- ...

and returns:

```python
{
    "screen": {
        "path": ".../frame_00000.png",
        "resolution": [1920, 1080],
        # optional when inline=true:
        "png_b64": "..."
    }
}
```

### `audio_waveform`

If configured and supported by the runner:

```python
{
    "audio": {
        "rate": 16000,
        "channels": 1,
        "num_samples": 3200,
        "s16le_b64": "..."
    }
}
```

### `ui_tree`

If the runner implements UI tree capture:

```python
{
    "ui_tree": {
        "text": "..."
    }
}
```

## Continuous Episode Recording

The env loop currently starts `FFmpegRecorder` only when both conditions are true:

- `recording.enable` is true
- the selected runner is `DockerRunner`

So today:

- Docker can produce live `recording.mp4`
- QEMU, AVD, and direct Apptainer can still produce `recording.mp4` from saved step screenshots when host `ffmpeg` is available

## Episode Artifacts

Typical episode directory contents:

```text
episode_<timestamp>_<uuid>/
├── frame_00000.png
├── frame_00001.png
├── ...
├── traj.jsonl
├── summary.json
├── final.png
├── post_verification.png         when finalization runs
├── recording.mp4                 live or screenshot-assembled video when available
└── ffmpeg.log                    when live Docker recording runs
```

If `diagnostics` is enabled, the runtime also tries to copy selected setup and system logs into the episode directory.

## Trajectory Log

`traj.jsonl` is event-based, not just step-based. It currently contains entries such as:

- `reset`
- `session`
- `step`
- `finalize`

Treat it as a useful artifact rather than a stable long-term schema contract.

## Pause And Resume

```python
env.pause_recording()
env.resume_recording()
```

These methods only affect the continuous FFmpeg recording handle. They do not disable the step screenshot capture used for observations.
