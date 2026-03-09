#!/bin/bash
echo "=== Setting up design_hawt_blade_multisection ==="

source /workspace/scripts/task_utils.sh

AIRFOIL_DIR="/home/ga/Documents/airfoils"
PROJECT_DIR="/home/ga/Documents/projects"
mkdir -p "$AIRFOIL_DIR" "$PROJECT_DIR"

# Distinct starting state: only naca0015.dat and naca4412.dat available
rm -f "$AIRFOIL_DIR"/naca2412.dat "$AIRFOIL_DIR"/naca6412.dat
rm -f "$AIRFOIL_DIR"/generated_*.dat "$AIRFOIL_DIR"/polar_*.txt

# Ensure required airfoils exist
for FOIL in naca0015 naca4412; do
    if [ ! -f "$AIRFOIL_DIR/${FOIL}.dat" ]; then
        if [ -f "/workspace/data/airfoils/${FOIL}.dat" ]; then
            cp "/workspace/data/airfoils/${FOIL}.dat" "$AIRFOIL_DIR/${FOIL}.dat"
            echo "Copied ${FOIL}.dat to airfoils directory"
        else
            echo "ERROR: ${FOIL}.dat not found in workspace data"
        fi
    fi
done

# Record baseline: hash all existing sample projects for anti-copy check
SAMPLE_HASHES=""
for wpa in /home/ga/Documents/sample_projects/*.wpa /opt/qblade/*/sample\ projects/*.wpa /opt/qblade/*/*/sample\ projects/*.wpa; do
    if [ -f "$wpa" ]; then
        h=$(md5sum "$wpa" 2>/dev/null | cut -d' ' -f1)
        SAMPLE_HASHES="${SAMPLE_HASHES}${h}\n"
    fi
done
echo -e "$SAMPLE_HASHES" > /tmp/initial_sample_hashes

# Record initial project count
INITIAL_WPA_COUNT=$(ls "$PROJECT_DIR"/*.wpa 2>/dev/null | wc -l)
echo "$INITIAL_WPA_COUNT" > /tmp/initial_wpa_count

# Remove previous output
rm -f "$PROJECT_DIR/my_hawt_blade.wpa"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Launch QBlade
launch_qblade
sleep 8
wait_for_qblade 30

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
