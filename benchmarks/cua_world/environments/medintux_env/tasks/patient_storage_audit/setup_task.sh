#!/bin/bash
set -e
echo "=== Setting up patient_storage_audit task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Define MedinTux paths
MEDINTUX_DIR="/home/ga/.wine/drive_c/MedinTux-2.16"
DRTUX_DIR="$MEDINTUX_DIR/DrTux"
PATIENT_FILES_DIR="$DRTUX_DIR/FichePatient"

# Ensure directories exist
mkdir -p "$PATIENT_FILES_DIR"

# Define test patients with specific heavy storage requirements
# Format: "GUID|Firstname|Lastname|SizeMB"
# We use fixed GUIDs to ensure deterministic behavior for verification, 
# but they look random to the agent.
declare -a PATIENTS=(
    "E4B8C1A0-9F2D-11EC-B909-0242AC120002|Michel|DURAND|120"
    "A1B2C3D4-E5F6-7890-1234-56789ABCDEF0|Sophie|MARTIN|85"
    "B2C3D4E5-F678-9012-3456-789ABCDEF012|Marie|LEFEBVRE|60"
    "C3D4E5F6-7890-1234-5678-9ABCDEF01234|Pierre|BERNARD|40"
    "D4E5F678-9012-3456-789A-BCDEF0123456|Francois|PETIT|15"
)

echo "Cleaning up previous test data..."
rm -f /home/ga/high_usage_patients.csv
# Clean DB
for p in "${PATIENTS[@]}"; do
    IFS='|' read -r guid first last size <<< "$p"
    mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$guid'" 2>/dev/null || true
    mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$guid'" 2>/dev/null || true
    # Remove directory if exists
    rm -rf "$PATIENT_FILES_DIR/$guid"
done

echo "Creating heavy patient records..."

for p in "${PATIENTS[@]}"; do
    IFS='|' read -r guid first last size <<< "$p"
    
    # 1. Insert into Database (so name resolution works)
    echo "  Inserting DB record for $first $last..."
    mysql -u root DrTuxTest -e \
        "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
         VALUES ('$guid', '$last', '$first', 'Dossier')"
         
    # 2. Create Directory structure
    PATIENT_DIR="$PATIENT_FILES_DIR/$guid"
    mkdir -p "$PATIENT_DIR"
    
    # 3. Create dummy content to consume space
    # We create a 'Scans' subdirectory to look realistic
    mkdir -p "$PATIENT_DIR/Scans"
    
    # Create a large dummy file using fallocate (fast) or dd (compatible)
    echo "  Allocating ${size}MB for $first $last..."
    if command -v fallocate >/dev/null; then
        fallocate -l "${size}M" "$PATIENT_DIR/Scans/scan_archive.tiff"
    else
        dd if=/dev/zero of="$PATIENT_DIR/Scans/scan_archive.tiff" bs=1M count=$size status=none
    fi
    
    # Add a small text file for realism
    echo "Patient record for $first $last" > "$PATIENT_DIR/info.txt"
done

# Launch MedinTux Manager so the system looks "alive"
echo "Launching MedinTux Manager..."
launch_medintux_manager

# Ensure permissions are correct for 'ga' user to read/write
chown -R ga:ga "$MEDINTUX_DIR"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="