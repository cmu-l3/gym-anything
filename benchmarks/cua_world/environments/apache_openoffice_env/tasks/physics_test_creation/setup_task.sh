#!/bin/bash
set -e
echo "=== Setting up Physics Test Creation Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. create necessary directories
mkdir -p /home/ga/Documents

# 2. Generate the Draft Text File
cat > /home/ga/Documents/exam_draft.txt << 'EOF'
EXAM DRAFT - UNIT 3
-------------------

HEADER INFO:
School: Westview Academy
Class: Physics 301 - Unit 3: Work and Energy

INSTRUCTIONS:
Please answer all questions. Show your work.

QUESTION 1:
Define Kinetic Energy and write the formula.
(Insert Formula here using code: K = {1} over {2} m v^2 )

QUESTION 2:
State the Work-Energy Theorem mathematically.
(Insert Formula here using code: W_{net} = Delta K )

QUESTION 3:
A roller coaster cart of mass m starts from rest at height h. It enters a loop-the-loop of radius R.
(Insert image roller_coaster.png here)
Calculate the minimum height h required for the cart to complete the loop without falling.

QUESTION 4:
Calculate the Gravitational Potential Energy of a 5kg block at a height of 10m.
(Insert Formula here using code: U_g = m g h )

EOF
chown ga:ga /home/ga/Documents/exam_draft.txt

# 3. Generate the Image (Roller Coaster Diagram)
# We use python to create a simple PNG if possible, or copy a placeholder
python3 -c "
import zlib, struct

def make_png(width, height):
    # minimal png generator to avoid external dependencies if possible
    # header
    header = b'\x89PNG\r\n\x1a\n'
    # IHDR
    ihdr = b'IHDR' + struct.pack('!2I5B', width, height, 8, 2, 0, 0, 0)
    ihdr_crc = struct.pack('!I', zlib.crc32(ihdr) & 0xffffffff)
    # IDAT (simple red pixels)
    # RGB triplets
    raw_data = b'\xff\x00\x00' * (width * height)
    # scanlines: 0 filter byte at start of each line
    scanlines = b''.join(b'\x00' + raw_data[i*width*3:(i+1)*width*3] for i in range(height))
    idat_data = zlib.compress(scanlines)
    idat = b'IDAT' + struct.pack('!I', len(idat_data)) + idat_data
    idat_crc = struct.pack('!I', zlib.crc32(idat) & 0xffffffff)
    # IEND
    iend = b'IEND\x00\x00\x00\x00'
    iend_crc = struct.pack('!I', zlib.crc32(iend) & 0xffffffff)
    
    return header + struct.pack('!I', len(ihdr)-4) + ihdr + ihdr_crc + idat + idat_crc + struct.pack('!I', 0) + iend + iend_crc

with open('/home/ga/Documents/roller_coaster.png', 'wb') as f:
    f.write(make_png(300, 200))
"
chown ga:ga /home/ga/Documents/roller_coaster.png

# 4. Clean up previous results
rm -f /home/ga/Documents/Physics_Unit3_Exam.odt

# 5. Record start time
date +%s > /tmp/task_start_time.txt

# 6. Ensure OpenOffice Writer is open (Blank Document)
if ! pgrep -f "soffice" > /dev/null; then
    echo "Starting OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
            break
        fi
        sleep 1
    done
fi

# Maximize
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="