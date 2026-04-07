#!/bin/bash
set -e

echo "=== Setting up HEC-RAS environment ==="

HECRAS_HOME="/opt/hec-ras"

# --- 1. Wait for desktop to be ready ---
sleep 5

# --- 2. Setup user directories ---
echo "--- Setting up user directories ---"
mkdir -p /home/ga/Documents/hec_ras_projects/Muncie
mkdir -p /home/ga/Documents/hec_ras_results
mkdir -p /home/ga/Documents/analysis_scripts

# --- 3. Copy Muncie example project to user home ---
echo "--- Copying Muncie example project ---"
if [ -d "$HECRAS_HOME/examples/Muncie" ]; then
    cp -r "$HECRAS_HOME/examples/Muncie"/* /home/ga/Documents/hec_ras_projects/Muncie/ 2>/dev/null || true

    # Copy wrk_source files to the working directory (these are the input files)
    cd /home/ga/Documents/hec_ras_projects/Muncie
    if [ -d "wrk_source" ]; then
        cp wrk_source/* . 2>/dev/null || true
        echo "  Copied wrk_source files to working directory"
    fi

    # List what we have
    echo "  Muncie project files:"
    ls -la /home/ga/Documents/hec_ras_projects/Muncie/
fi

# --- 4. Copy analysis scripts ---
echo "--- Copying analysis scripts ---"
if [ -d "$HECRAS_HOME/analysis_scripts" ]; then
    cp "$HECRAS_HOME/analysis_scripts"/*.py /home/ga/Documents/analysis_scripts/ 2>/dev/null || true
fi
# Also copy from workspace (in case install didn't copy)
cp /workspace/data/analysis_scripts/*.py /home/ga/Documents/analysis_scripts/ 2>/dev/null || true
chmod +x /home/ga/Documents/analysis_scripts/*.py 2>/dev/null || true

# --- 5. Create HEC-RAS launcher script ---
echo "--- Creating launcher scripts ---"
cat > /home/ga/Desktop/run_hecras_sim.sh << 'EOF'
#!/bin/bash
# HEC-RAS Simulation Runner
source /etc/profile.d/hec-ras.sh
cd /home/ga/Documents/hec_ras_projects/Muncie

echo "=== HEC-RAS Muncie Simulation ==="
echo "Available executables:"
echo "  RasGeomPreprocess - Geometry preprocessor"
echo "  RasUnsteady       - Unsteady flow solver"
echo "  RasSteady         - Steady flow solver"
echo ""
echo "Project files:"
ls -la *.??* 2>/dev/null
echo ""
echo "Usage examples:"
echo "  RasUnsteady Muncie.p04.tmp.hdf x04"
echo "  RasSteady Muncie.r04"
echo "  RasGeomPreprocess Muncie.p04.tmp.hdf x04"
EOF
chmod +x /home/ga/Desktop/run_hecras_sim.sh

# --- 6. Create desktop shortcut for terminal ---
cat > /home/ga/Desktop/HEC-RAS-Terminal.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Type=Application
Name=HEC-RAS Terminal
Comment=Open terminal in HEC-RAS project directory
Exec=gnome-terminal --working-directory=/home/ga/Documents/hec_ras_projects/Muncie
Icon=utilities-terminal
Terminal=false
Categories=Engineering;Science;
DESKTOP_EOF
chmod +x /home/ga/Desktop/HEC-RAS-Terminal.desktop

# Mark desktop shortcuts as trusted (GNOME)
su - ga -c "DISPLAY=:1 gio set /home/ga/Desktop/HEC-RAS-Terminal.desktop metadata::trusted true" 2>/dev/null || true

# --- 7. Set environment variables for user ---
echo "--- Configuring user environment ---"
cat >> /home/ga/.bashrc << 'BASHRC_EOF'

# HEC-RAS environment
export HECRAS_HOME="/opt/hec-ras"
export PATH="$HECRAS_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$HECRAS_HOME/lib:$HECRAS_HOME/lib/mkl:$HECRAS_HOME/lib/rhel_8:$LD_LIBRARY_PATH"

# Convenient aliases
alias hecras-project='cd /home/ga/Documents/hec_ras_projects/Muncie'
alias hecras-results='cd /home/ga/Documents/hec_ras_results'
alias hecras-scripts='cd /home/ga/Documents/analysis_scripts'
BASHRC_EOF

# --- 8. Set correct permissions ---
echo "--- Setting permissions ---"
chown -R ga:ga /home/ga/Documents/hec_ras_projects
chown -R ga:ga /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/analysis_scripts
chown -R ga:ga /home/ga/Desktop

# --- 9. Configure gedit for better code editing ---
su - ga -c "DISPLAY=:1 gsettings set org.gnome.gedit.preferences.editor display-line-numbers true" 2>/dev/null || true
su - ga -c "DISPLAY=:1 gsettings set org.gnome.gedit.preferences.editor highlight-current-line true" 2>/dev/null || true
su - ga -c "DISPLAY=:1 gsettings set org.gnome.gedit.preferences.editor tabs-size 4" 2>/dev/null || true

# --- 10. Verify setup ---
echo "--- Verifying setup ---"
echo "Project files in Muncie directory:"
ls -la /home/ga/Documents/hec_ras_projects/Muncie/ 2>/dev/null || echo "  (empty)"
echo "Analysis scripts:"
ls -la /home/ga/Documents/analysis_scripts/ 2>/dev/null || echo "  (empty)"
echo "HEC-RAS executables accessible:"
su - ga -c "source /etc/profile.d/hec-ras.sh && which RasUnsteady 2>/dev/null" || echo "  (not in PATH)"

# Verify libraries resolve
echo "Library check:"
su - ga -c "source /etc/profile.d/hec-ras.sh && ldd /opt/hec-ras/bin/RasUnsteady 2>&1 | grep 'not found'" || echo "  All libraries resolved"

echo "=== HEC-RAS setup complete ==="
