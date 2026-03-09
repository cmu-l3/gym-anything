FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium-browser chromium-codecs-ffmpeg \
    xvfb x11-apps x11-utils xdotool fluxbox \
    pulseaudio ffmpeg x11vnc curl jq \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY start_browser.sh /workspace/start_browser.sh
RUN chmod +x /workspace/start_browser.sh

