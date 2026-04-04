#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Embed External Media Task ==="

# Define paths
ASSETS_DIR="/home/ga/Documents/Assets"
PRES_DIR="/home/ga/Documents/Presentations"
PRES_FILE="$PRES_DIR/company_overview.odp"

# Create directories
sudo -u ga mkdir -p "$ASSETS_DIR"
sudo -u ga mkdir -p "$PRES_DIR"

# 1. Generate Assets
echo "Generating assets..."

# Generate a PNG logo
su - ga -c "convert -size 400x100 xc:transparent -font DejaVu-Sans-Bold -pointsize 40 -fill blue -draw \"text 20,60 'COMPANY LOGO'\" \"$ASSETS_DIR/logo_brand.png\""

# Generate a dummy MP3 audio file (10 seconds of silence/tone)
# Using ffmpeg lavfi to generate a sine wave
if command -v ffmpeg &> /dev/null; then
    su - ga -c "ffmpeg -f lavfi -i \"sine=frequency=440:duration=5\" -c:a libmp3lame -q:a 4 -y \"$ASSETS_DIR/intro_music.mp3\" 2>/dev/null"
else
    # Fallback if ffmpeg is missing (create empty file, though this might fail valid audio checks)
    su - ga -c "touch \"$ASSETS_DIR/intro_music.mp3\""
fi

# 2. Create ODP with LINKED media using Python
# We explicitly construct an ODP that references external files via file:// URLs
echo "Creating presentation with linked media..."

python3 << PYEOF
import os
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, Image, Plugin
from odf.text import P
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties

# Paths
assets_dir = "$ASSETS_DIR"
logo_path = os.path.join(assets_dir, "logo_brand.png")
audio_path = os.path.join(assets_dir, "intro_music.mp3")
save_path = "$PRES_FILE"

# Create doc
doc = OpenDocumentPresentation()

# Slide 1
page = Page(name="Slide1")
doc.presentation.addElement(page)

# Title
frame_title = Frame(width="720pt", height="56pt", x="56pt", y="42pt")
textbox_title = doc.content.createElement("draw:text-box")
p_title = P(text="Company Overview")
textbox_title.addElement(p_title)
frame_title.addElement(textbox_title)
page.addElement(frame_title)

# LINKED Image (Logo)
# We use a file URI. Important: odfpy by default doesn't embed if we just pass href
logo_uri = f"file://{logo_path}"
frame_img = Frame(width="10cm", height="2.5cm", x="2cm", y="5cm", name="LinkedLogo")
image = Image(href=logo_uri)
frame_img.addElement(image)
page.addElement(frame_img)

# LINKED Audio
# Audio is typically a draw:plugin or draw:frame with a plugin
audio_uri = f"file://{audio_path}"
frame_audio = Frame(width="1cm", height="1cm", x="1cm", y="1cm", name="LinkedAudio")
plugin = Plugin(href=audio_uri, mimetype="audio/mpeg")
frame_audio.addElement(plugin)
page.addElement(frame_audio)

# Save
doc.save(save_path)
print(f"Created {save_path} with links to {logo_uri} and {audio_uri}")
PYEOF

# Fix permissions
sudo chown -R ga:ga "$PRES_DIR"
sudo chown -R ga:ga "$ASSETS_DIR"

# Record initial state
date +%s > /tmp/task_start_time.txt
stat -c %s "$PRES_FILE" > /tmp/initial_file_size.txt

# 3. Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress \"$PRES_FILE\" > /tmp/impress_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 90

# Focus window and ensure it's ready
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Click to ensure focus on the slide pane
    safe_xdotool ga :1 mousemove 600 600 click 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="
echo "The presentation is open."
echo "Media files are currently LINKED to: $ASSETS_DIR"
echo "Your task is to EMBED them."