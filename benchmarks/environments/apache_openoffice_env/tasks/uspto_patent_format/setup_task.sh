#!/bin/bash
set -e
echo "=== Setting up USPTO Patent Format Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# 2. Clean up any previous artifacts
rm -f /home/ga/Documents/NeuroSync_Patent_App.odt
rm -f /home/ga/Documents/patent_draft.txt
rm -f /home/ga/Documents/firm_style_guide.txt

# 3. Create the raw patent draft text file
cat > /home/ga/Documents/patent_draft.txt << 'EOF'
SYSTEM AND METHOD FOR ADAPTIVE HAPTIC FEEDBACK IN VIRTUAL ENVIRONMENTS

FIELD OF THE INVENTION
The present invention relates generally to haptic interface devices, and more particularly to a system for providing adaptive tactile feedback based on virtual surface texture and user grip force.

BACKGROUND OF THE INVENTION
Virtual reality (VR) and augmented reality (AR) systems have advanced significantly in visual and auditory fidelity. However, haptic feedback remains a challenge. Conventional controllers use simple vibration motors (rumble packs) which fail to convey realistic texture or resistance.
Existing solutions using linear resonant actuators (LRAs) or piezoelectric elements often lack the dynamic range to simulate both coarse textures (like concrete) and fine textures (like silk) effectively. There is a need for a haptic controller that adapts its frequency response in real-time.

SUMMARY OF THE INVENTION
The present invention addresses these limitations by providing a haptic interface comprising a multi-axis force sensor and a high-bandwidth voice coil actuator. A local control loop adjusts the actuation signal based on detected grip force, ensuring consistent tactile sensation regardless of how tightly the user holds the device.

BRIEF DESCRIPTION OF THE DRAWINGS
FIG. 1 is a block diagram of the haptic feedback system.
FIG. 2 is a flowchart of the adaptive control algorithm.

DETAILED DESCRIPTION OF THE PREFERRED EMBODIMENTS
In one embodiment, the system includes a controller housing having a grip portion. Embedded within the grip portion is a pressure-sensitive array configured to measure the user's grip intensity map.
The processor receives texture data from the VR simulation engine. If the user's grip is loose, the amplitude of the high-frequency components is increased to ensure transmissibility to the skin. If the grip is tight, the amplitude is modulated to prevent saturation.

CLAIMS
1. A haptic feedback system comprising:
a handheld housing;
a force sensor array disposed on a surface of the housing;
an actuator configured to generate tactile vibrations; and
a processor configured to modulate an actuation signal based on data from the force sensor array.
2. The system of claim 1, wherein the actuator is a voice coil actuator.
3. The system of claim 1, further comprising a wireless communication module for receiving texture data from a host computer.
4. A method of providing adaptive haptic feedback, comprising:
measuring a grip force exerted by a user;
receiving a virtual texture parameter;
calculating a compensation factor based on the grip force; and
driving an actuator using the texture parameter scaled by the compensation factor.

ABSTRACT
A system for providing adaptive haptic feedback in a virtual environment includes a handheld controller with embedded force sensors and a wide-bandwidth actuator. The system dynamically adjusts the characteristics of the tactile vibrations based on the user's real-time grip force to maintain consistent perceived texture fidelity.
EOF
chown ga:ga /home/ga/Documents/patent_draft.txt

# 4. Create the Style Guide for reference (optional, but helpful context)
cat > /home/ga/Documents/firm_style_guide.txt << 'EOF'
SUMMIT IP LAW GROUP - PATENT SPECIFICATION FORMATTING GUIDE

1. PAGE SETUP
   - Margins: 1.0" (2.54 cm) on all sides (Top, Bottom, Left, Right).
   - Paper Size: Letter or A4.

2. TEXT FORMATTING
   - Font: Times New Roman or Arial, 12 point.
   - Line Spacing: Double spaced (2.0).
   - Text color: Black.

3. LINE NUMBERING
   - Mandatory for all specification pages.
   - Must appear in the left margin.
   - Increment: Every 1 or 5 lines (OpenOffice "Show numbering").

4. SECTION HEADINGS
   - Must be All Caps and Bold.
   - Do not underline.

5. CLAIMS
   - Must start on a new page or be clearly separated.
   - Must be a numbered list (1., 2., 3., ...).

6. ABSTRACT
   - Must be on a separate page (insert Page Break).
   - Maximum 150 words.
EOF
chown ga:ga /home/ga/Documents/firm_style_guide.txt

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Ensure OpenOffice Writer is open with a blank document
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

# 7. Maximize the window
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="