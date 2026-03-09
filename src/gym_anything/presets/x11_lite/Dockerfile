FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb x11-apps x11-utils xdotool fluxbox pulseaudio ffmpeg xterm x11vnc \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY start_app.sh /workspace/start_app.sh
COPY hooks/ /workspace/hooks/
RUN chmod +x /workspace/start_app.sh && chmod +x /workspace/hooks/*.sh || true

