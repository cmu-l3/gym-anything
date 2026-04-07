# Example: Basic X11 Docker Environment

This minimal environment demonstrates `DockerRunner` + FFmpeg recording.
It launches an Ubuntu container with Xvfb, fluxbox, xclock, and xterm.

## Files
- `env.json` – EnvSpec pointing to the Dockerfile and scripts
- `Dockerfile` – installs Xvfb, fluxbox, xdotool, pulseaudio, ffmpeg, x11 apps
- `scripts/start_app.sh` – starts fluxbox, xclock, xterm (uses `$DISPLAY`)
- `scripts/reset_env.sh` – placeholder reset hook

Artifacts (video, logs) will appear under `examples/docker_env/artifacts/episode_*`.

## Build & Run

1) Build the image (done automatically when using `dockerfile` via API):

- `from_config()` calls `DockerRunner._build_image()` if only `dockerfile` is present.

2) Run the Python example:

```
python examples/run_docker_example.py
```

This will:
- Build the image (first run), start a container, Xvfb, and PulseAudio
- Start fluxbox + xclock + xterm
- Inject a few mouse/keyboard actions
- Record screen + (silent) audio to MP4 in artifacts

## View via VNC (optional)

VNC is enabled in `env.json` (`vnc.enable=true`). The container exposes port 5900
mapped to host port 5901. Use any VNC viewer to connect:

- Host: `localhost`
- Port: `5901`
- Password: none (by default)

Set `vnc.view_only=true` (recommended) to prevent interactions by the viewer.
You can set a password by adding `"password": "yourpass"` under `vnc` in `env.json`.

## Notes
- Recording requires `ffmpeg` inside the container (installed by Dockerfile).
- Actions use `xdotool`; ensure apps are visible on the virtual display.
- Network is disabled by default (`resources.net=false`).
- The container runs as `root` in this example for simplicity.
