#!/bin/bash
set -e

echo "=== Setting up brand_template_creation ==="

source /workspace/scripts/task_utils.sh

sudo -u ga mkdir -p /home/ga/Documents

python3 <<'PY'
import base64
from pathlib import Path

png_data = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAGQAAAAoCAIAAAD+MdrbAAAACXBIWXMAAAsSAAALEgHS3X78AAAA"
    "B3RJTUUH6gMIBQs0NE6PFQAAAB1pVFh0Q29tbWVudAAAAAAAvK6ymQAAABl0RVh0U29mdHdhcmUA"
    "QWRvYmUgSW1hZ2VSZWFkeXHJZTwAAAEKSURBVHja7NixDcIwEATQx0mYQ7v/ka1K2EEA5HZXDBln"
    "2WnPpnQ2Hkt1m9vbLwAAAAAAAAAAwL2p0v8bpSx3v9wYhW6P0m6s3j6X0w8x6U7o4W4wqJQm7hQ0G"
    "B0w2xgN5M4Qe5gNoL2hJ9tT3V7v7z5u2m1p2r9S8w3TgYhP1hG1u1y7m4E6K1R1w7vV4k0g1mO5pX"
    "H6nq8Q7C9H3S3w1GJc2q7cC+vQStQ3Aq0Fq6k9f3sM9a9lH6Q4s2w9wXKk0Xw6rE5N2f1+N9p4vL3"
    "4X3X1wAAAAAAAAAAwL8B3nABzqD5Q5EAAAAASUVORK5CYII="
)
Path("/home/ga/Documents/apex_logo.png").write_bytes(png_data)
PY

chown ga:ga /home/ga/Documents/apex_logo.png
date +%s > /tmp/brand_template_creation_start_ts

pkill -f soffice 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 libreoffice --writer --norestore > /tmp/brand_template_creation_writer.log 2>&1 &"

wait_for_window "LibreOffice Writer" 60 || wait_for_window "Untitled 1" 30 || wait_for_window "Untitled" 30

wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/brand_template_creation_start.png

echo "=== Setup complete ==="
