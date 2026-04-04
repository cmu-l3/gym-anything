#!/bin/bash
set -e
echo "=== Setting up Film Call Sheet Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Documents directory and clean up
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/Call_Sheet_Day_14.odt 2>/dev/null || true
rm -f /home/ga/Documents/production_data.json 2>/dev/null || true
rm -f /home/ga/Documents/production_logo.png 2>/dev/null || true

# 2. Generate Production Data JSON
cat > /home/ga/Documents/production_data.json << 'EOF'
{
  "production": {
    "title": "The Midnight Echo",
    "date": "October 24, 2025",
    "day_x_of_y": "Day 14 of 24",
    "producers": ["J. Bruckheimer", "K. Kennedy"],
    "director": "C. Nolanish",
    "general_crew_call": "07:00 AM"
  },
  "locations": [
    {
      "name": "The Old Cannery",
      "address": "450 Industrial Way, Seattle, WA",
      "notes": "Basecamp in South Lot"
    }
  ],
  "weather": {
    "forecast": "Heavy fog in morning, clearing to rain.",
    "temp": "High 52F / Low 45F",
    "sunrise": "07:12 AM",
    "sunset": "06:04 PM"
  },
  "hospitals": [
    {
      "name": "Harborview Medical Center",
      "address": "325 9th Ave, Seattle, WA 98104",
      "phone": "(206) 744-3000"
    }
  ],
  "schedule": [
    {
      "scene": "42",
      "set": "INT. BASEMENT - INTERROGATION",
      "cast_ids": "1, 3",
      "day_night": "DAY",
      "pages": "4/8",
      "notes": "Atmospheric smoke required"
    },
    {
      "scene": "44A",
      "set": "EXT. LOADING DOCK - ESCAPE",
      "cast_ids": "1, 3, 5",
      "day_night": "NIGHT",
      "pages": "2 1/8",
      "notes": "Stunts / Wetdown"
    }
  ],
  "cast": [
    {
      "id": 1,
      "character": "VANYA",
      "actor": "Elena Rostova",
      "pickup": "05:45",
      "hair_makeup": "06:15",
      "set_call": "07:00"
    },
    {
      "id": 3,
      "character": "DET. MILLER",
      "actor": "Marcus Thorne",
      "pickup": "06:30",
      "hair_makeup": "07:00",
      "set_call": "07:30"
    },
    {
      "id": 5,
      "character": "VANYA DBL",
      "actor": "Stunt Performer",
      "pickup": "N/A",
      "hair_makeup": "08:00",
      "set_call": "09:00"
    }
  ],
  "department_notes": {
    "Camera": "Two cameras required for Sc 44A.",
    "Sound": "Playback required for basement sequence.",
    "Art": "Reset breakables for Sc 42 takes."
  }
}
EOF
chown ga:ga /home/ga/Documents/production_data.json

# 3. Generate a dummy Logo PNG using Python (blue circle on white background)
# This avoids dependency on ImageMagick if not present
python3 -c '
import struct, zlib

def png_pack(png_tag, data):
    chunk_head = png_tag + data
    return struct.pack("!I", len(data)) + chunk_head + struct.pack("!I", 0xFFFFFFFF & zlib.crc32(chunk_head))

width, height = 200, 100
# RGB image, 3 bytes per pixel
raw_data = b""
for y in range(height):
    # Filter byte 0 (None) at start of each scanline
    raw_data += b"\x00" 
    for x in range(width):
        # Blueish gradient
        raw_data += struct.pack("BBB", 0, x % 255, 128)

compressed_data = zlib.compress(raw_data)
png_data = b"\x89PNG\r\n\x1a\n"
png_data += png_pack(b"IHDR", struct.pack("!IIBBB", width, height, 8, 2, 0, 0, 0))
png_data += png_pack(b"IDAT", compressed_data)
png_data += png_pack(b"IEND", b"")

with open("/home/ga/Documents/production_logo.png", "wb") as f:
    f.write(png_data)
'
chown ga:ga /home/ga/Documents/production_logo.png

# 4. Record task start time
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_exists

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Data: /home/ga/Documents/production_data.json"
echo "Logo: /home/ga/Documents/production_logo.png"