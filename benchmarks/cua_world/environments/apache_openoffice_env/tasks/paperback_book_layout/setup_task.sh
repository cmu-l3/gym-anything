#!/bin/bash
# setup_task.sh for paperback_book_layout

echo "=== Setting up Paperback Book Layout Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up previous artifacts
rm -f /home/ga/Documents/The_Echoing_Void_Formatted.odt 2>/dev/null || true
rm -f /home/ga/Documents/manuscript_raw.txt 2>/dev/null || true
rm -f /home/ga/Documents/print_specs.json 2>/dev/null || true

# 1. Create the Raw Manuscript (Text File)
cat > /home/ga/Documents/manuscript_raw.txt << 'EOF'
CHAPTER 1

The comms array was down again. Kael swore under his breath, the sound harsh in the cramped silence of the cockpit. He tapped the gauge with a gloved knuckle, but the needle remained dead, resting heavily against the zero pin.

"Are we blind?" Elara asked. She didn't look up from her navigation console, but the tension in her shoulders was visible even through the thick flight suit.

"Worse," Kael muttered, flipping the breaker switch. "We're deaf. Assuming anyone is out there listening."

The ship, a battered freighter named the 'Rusty Starling', groaned as it settled into the gravity well of the moon below. It was a standard mining run, or it was supposed to be. But the anomalies in Sector 7 had been playing havoc with their electronics for the last three cycles.

Kael pulled the manual release for the landing struts. A mechanical clunk reverberated through the hull. "Struts are locked. Initiating descent sequence."

The viewscreen flickered, static washing over the starfield before resolving into the grey, cratered surface of XJ-492. It wasn't much to look at—just another rock floating in the dark—but the scans promised iridium, and the Guild paid well for refined ore.

"Atmospheric entry in ten," Elara announced. "Hold onto something."

The turbulence hit them like a physical blow. The Starling rattled, metal groaning against the stress. Kael fought the yoke, his knuckles white. "Stabilizers are at eighty percent. Compensating."

Through the shaking viewport, the horizon tilted crazily. Kael corrected, sweat beading on his forehead. This wasn't just turbulence; something was pulling at them, a magnetic shear that wasn't on the charts.

"Kael, look at the energy readings!" Elara yelled over the roar of the engines.

He glanced at the secondary monitor. The graph was spiking off the scale. "What is that? Interference?"

"No," she said, her voice dropping to a whisper. "It's a signal. A patterned signal."

They weren't alone.

The landing was rougher than Kael would have liked, kicking up a plume of grey dust that obscured the sensors for a long moment. When the engines finally cycled down, the silence that returned was absolute.

Kael unbuckled, his harness retreating with a snap. "Did you record it?"

"The signal?" Elara was already typing furiously. "Yes. It stopped the moment we touched down."

"Play it back."

She hesitated, then pressed a key. The cockpit speakers crackled. At first, it sounded like random noise—static, the hum of radiation. But then, a rhythm emerged. Three sharp pulses. A pause. Three long drones. A pause. Three sharp pulses.

"SOS," Kael said. "Old Earth code."

"Who uses that out here?" Elara asked. "The nearest human settlement is four sectors away."

Kael stood up and grabbed his helmet from the rack. "We're going to find out. Keep the engines hot. If this is a trap, I want to be airborne in seconds."

"And if it's not a trap?"

Kael looked at the airlock door. "Then someone down there is in a lot of trouble."

The airlock cycled with a hiss of equalizing pressure. Kael stepped out onto the landing ramp, the magnetic boots of his suit clamping onto the metal with each step. The gravity on XJ-492 was low, about 0.6 standard, giving his movements a strange, floating quality.

Dust swirled around his visor. The landscape was desolate—jagged spires of rock rising from the grey plains like skeletal fingers. The scanner in his HUD pinged, highlighting a faint heat signature two klicks north.

"I have a visual on the source," Kael radioed. "Structure of some kind. Looks crashed."

"Be careful," Elara's voice crackled in his ear. "I'm reading energy fluctuations near that location. Same signature as the signal."

Kael trudged forward, the dust crunching under his boots. As he got closer, the shape resolved. It wasn't a ship. It was a beacon, ancient and weathered, half-buried in the regolith. But it was pulsing with a faint blue light.

He reached out to touch the metallic surface. It was cold, smoother than any alloy he knew. He wiped away a layer of grime, revealing an inscription etched into the metal.

"Elara," he said, his voice trembling slightly. "You're not going to believe this."

"What is it?"

"It's not a distress beacon," Kael said, reading the words that shouldn't exist, not here, not this far from home. "It's a warning."
EOF
chown ga:ga /home/ga/Documents/manuscript_raw.txt

# 2. Create Print Specifications JSON
cat > /home/ga/Documents/print_specs.json << 'EOF'
{
  "book_metadata": {
    "title": "THE ECHOING VOID",
    "author": "J.R. BLACKWOOD",
    "genre": "Science Fiction"
  },
  "layout_requirements": {
    "page_size": {
      "width": "6.00 inches",
      "height": "9.00 inches",
      "standard_name": "Trade Paperback"
    },
    "margins": {
      "style": "Mirrored",
      "inside_gutter": "0.80 inches",
      "outside": "0.50 inches",
      "top": "0.75 inches",
      "bottom": "0.75 inches"
    },
    "headers": {
      "even_page_content": "J.R. BLACKWOOD",
      "odd_page_content": "THE ECHOING VOID",
      "alignment": "Center"
    },
    "footer": {
      "content": "Page Number",
      "alignment": "Center"
    }
  },
  "typography": {
    "paragraph_style": {
      "alignment": "Justified",
      "first_line_indent": "0.25 inches",
      "spacing_between_paragraphs": "0 (None)"
    }
  }
}
EOF
chown ga:ga /home/ga/Documents/print_specs.json

# 3. Create Desktop Shortcut for Writer
if [ -x "/opt/openoffice4/program/soffice" ]; then
    cat > /home/ga/Desktop/openoffice-writer.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenOffice Writer
Comment=Create and edit text documents
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=/opt/openoffice4/program/soffice
Terminal=false
Categories=Office;WordProcessor;
DESKTOP
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
fi

# 4. Record Initial State
echo "0" > /tmp/initial_file_exists
date +%s > /tmp/task_start_time.txt

# 5. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Manuscript: /home/ga/Documents/manuscript_raw.txt"
echo "Specs: /home/ga/Documents/print_specs.json"