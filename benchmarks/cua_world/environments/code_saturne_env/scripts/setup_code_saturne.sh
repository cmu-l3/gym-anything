#!/bin/bash
set -e

echo "=== Setting up Code_Saturne ==="

# Wait for desktop to be ready
sleep 5

TUTORIALS_DIR="/opt/code_saturne_tutorials"
STUDY_DIR="/home/ga/CFD_Studies"

# Create a study directory structure for the user
echo "Setting up CFD study directory..."
mkdir -p "$STUDY_DIR"
chown ga:ga "$STUDY_DIR"

# Create a Code_Saturne study using the official command
# code_saturne create creates: STUDY_NAME/MESH/ and STUDY_NAME/CASE1/ (uppercase CASE1)
TMPDIR=$(mktemp -d)
chown ga:ga "$TMPDIR"
su - ga -c "cd $TMPDIR && code_saturne create -s TJunction_Study" 2>&1 || true

# Move the created study or create manually
if [ -d "$TMPDIR/TJunction_Study" ]; then
    # Remove any pre-existing directory to allow move
    rm -rf "$STUDY_DIR/TJunction_Study" 2>/dev/null || true
    mv "$TMPDIR/TJunction_Study" "$STUDY_DIR/"
    echo "Moved TJunction_Study to $STUDY_DIR"
else
    echo "code_saturne create failed, setting up manually..."
    mkdir -p "$STUDY_DIR/TJunction_Study/MESH"
    mkdir -p "$STUDY_DIR/TJunction_Study/CASE1/DATA"
    mkdir -p "$STUDY_DIR/TJunction_Study/CASE1/SRC"
    mkdir -p "$STUDY_DIR/TJunction_Study/CASE1/RESU"
    mkdir -p "$STUDY_DIR/TJunction_Study/CASE1/SCRIPTS"
fi
rm -rf "$TMPDIR"

# Detect the case directory name (CASE1 or case1)
CASE_DIR=""
if [ -d "$STUDY_DIR/TJunction_Study/CASE1" ]; then
    CASE_DIR="CASE1"
elif [ -d "$STUDY_DIR/TJunction_Study/case1" ]; then
    CASE_DIR="case1"
else
    # Create it manually
    CASE_DIR="CASE1"
    mkdir -p "$STUDY_DIR/TJunction_Study/$CASE_DIR/DATA"
fi
echo "Case directory: $CASE_DIR"

# Copy real tutorial mesh data into the study
if [ -f "$TUTORIALS_DIR/01_Simple_Junction/MESH/downcomer.med" ]; then
    cp "$TUTORIALS_DIR/01_Simple_Junction/MESH/downcomer.med" \
        "$STUDY_DIR/TJunction_Study/MESH/"
    echo "Copied downcomer.med mesh to study MESH directory"
fi

# Copy the tutorial setup.xml (real configuration data)
if [ -f "$TUTORIALS_DIR/01_Simple_Junction/case1/DATA/setup.xml" ]; then
    cp "$TUTORIALS_DIR/01_Simple_Junction/case1/DATA/setup.xml" \
        "$STUDY_DIR/TJunction_Study/$CASE_DIR/DATA/"
    echo "Copied setup.xml to study DATA directory"
fi

# Copy run configuration
if [ -f "$TUTORIALS_DIR/01_Simple_Junction/case1/DATA/run.cfg" ]; then
    cp "$TUTORIALS_DIR/01_Simple_Junction/case1/DATA/run.cfg" \
        "$STUDY_DIR/TJunction_Study/$CASE_DIR/DATA/"
    echo "Copied run.cfg to study DATA directory"
fi

# Store the case directory name for task scripts to use
echo "$CASE_DIR" > "$STUDY_DIR/TJunction_Study/.case_dir_name"

# Set permissions for the ga user
chown -R ga:ga "$STUDY_DIR"
chmod -R 755 "$STUDY_DIR"

# Create a desktop shortcut for Code_Saturne GUI
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/code_saturne_gui.desktop << EOF
[Desktop Entry]
Name=Code_Saturne GUI
Comment=Launch Code_Saturne GUI for CFD setup
Exec=bash -c 'cd /home/ga/CFD_Studies/TJunction_Study/$CASE_DIR/DATA && DISPLAY=:1 code_saturne gui setup.xml'
Icon=applications-science
Terminal=false
Type=Application
Categories=Science;Engineering;
EOF
chmod +x /home/ga/Desktop/code_saturne_gui.desktop
chown ga:ga /home/ga/Desktop/code_saturne_gui.desktop

# Mark desktop file as trusted (suppress GNOME untrusted dialog)
su - ga -c "DISPLAY=:1 dbus-launch gio set /home/ga/Desktop/code_saturne_gui.desktop metadata::trusted true" 2>/dev/null || true

echo "=== Code_Saturne setup complete ==="
echo "Study directory: $STUDY_DIR"
echo "T-Junction study: $STUDY_DIR/TJunction_Study/"
echo "Case directory: $CASE_DIR"
ls -la "$STUDY_DIR/TJunction_Study/MESH/" 2>/dev/null || echo "No mesh files found"
ls -la "$STUDY_DIR/TJunction_Study/$CASE_DIR/DATA/" 2>/dev/null || echo "No DATA files found"
