#!/bin/bash
set -e

echo "=== Setting up Genetic Pedigree Task ==="

# Ensure directories exist
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# 1. Create Data File
cat > /home/ga/Desktop/pedigree_data.txt << 'EOF'
ROYAL HEMOPHILIA LINEAGE DATA
=============================

GENERATION I
1. Queen Victoria (Female) - Carrier
2. Prince Albert (Male) - Unaffected

GENERATION II (Children of Victoria & Albert)
1. Victoria (Princess Royal) (Female) - Unaffected (Spouse: Frederick III)
2. Edward VII (Male) - Unaffected (Spouse: Alexandra)
3. Princess Alice (Female) - Carrier (Spouse: Louis IV)
4. Prince Leopold (Male) - Affected (Spouse: Helena)
5. Princess Beatrice (Female) - Carrier (Spouse: Henry)

GENERATION III (Selected Grandchildren)
From Alice:
- Friedrich of Hesse (Male) - Affected
- Irene of Hesse (Female) - Carrier
- Alexandra (Alix) of Hesse (Female) - Carrier (Spouse: Nicholas II of Russia)

From Leopold:
- Alice of Albany (Female) - Carrier
- Charles Edward (Male) - Unaffected

From Beatrice:
- Alfonso of Battenberg (Male) - Affected
- Leopold of Battenberg (Male) - Affected
- Victoria Eugenie (Female) - Carrier (Spouse: Alfonso XIII of Spain)

GENERATION IV (Selected Great-Grandchildren)
From Alexandra (Russia):
- Tsarevich Alexei (Male) - Affected
- Grand Duchesses Olga, Tatiana, Maria, Anastasia (Females) - Status uncertain/Carrier

From Irene:
- Waldemar (Male) - Affected
- Heinrich (Male) - Affected

From Victoria Eugenie (Spain):
- Infante Alfonso (Male) - Affected
- Infante Gonzalo (Male) - Affected

From Alice of Albany:
- Rupert (Male) - Affected
EOF
chown ga:ga /home/ga/Desktop/pedigree_data.txt
chmod 644 /home/ga/Desktop/pedigree_data.txt

# 2. Create Conventions File
cat > /home/ga/Desktop/pedigree_conventions.txt << 'EOF'
GENETIC PEDIGREE NOTATION STANDARDS
===================================

SHAPES:
- Male: Square
- Female: Circle (Ellipse)
- Sex Unknown: Diamond (if applicable)

FILL / STATUS:
- Unaffected: Empty / White fill with black outline
- Affected: Solid Dark fill (Black/Gray/Red)
- Carrier (Obligate): Dot in center OR Half-filled OR distinct pattern (must be distinguishable from Affected and Unaffected)
- Deceased: Diagonal slash (Optional)

CONNECTIONS:
- Mating Line: Horizontal line connecting a male and female
- Descent Line: Vertical line descending from mating line
- Sibship Line: Horizontal line connecting siblings

LABELS:
- Generations: Roman numerals (I, II, III, IV) on the left margin
- Individuals: Name labels below or inside symbols
EOF
chown ga:ga /home/ga/Desktop/pedigree_conventions.txt
chmod 644 /home/ga/Desktop/pedigree_conventions.txt

# 3. Clean previous outputs
rm -f /home/ga/Diagrams/royal_hemophilia_pedigree.drawio
rm -f /home/ga/Diagrams/royal_hemophilia_pedigree.pdf

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch draw.io
echo "Launching draw.io..."
# Kill any existing instances
pkill -f drawio 2>/dev/null || true
sleep 1

# Launch as ga user
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /tmp/drawio_launch.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Dismiss update dialogs aggressively
# (Common in draw.io AppImage)
echo "Dismissing potential update dialogs..."
sleep 5
for i in {1..5}; do
    # Try Escape
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    # Try Tab -> Enter (Cancel button often reachable via tab)
    DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
    sleep 0.5
done

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="