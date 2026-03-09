#!/bin/bash
set -euo pipefail

echo "=== Setting up FreeCAD environment ==="

# Wait for desktop to be fully ready
sleep 5

# ============================================================
# Layer 1: Pre-configure FreeCAD to suppress first-run dialogs
# ============================================================

# Create FreeCAD config directories
mkdir -p /home/ga/.FreeCAD
mkdir -p /home/ga/.config/FreeCAD

# Write user.cfg (XML format, FreeCAD 0.19+)
# This suppresses the Start Center and sets Part workbench as default
cat > /home/ga/.FreeCAD/user.cfg << 'XMLEOF'
<?xml version='1.0' encoding='utf-8'?>
<FCParameters>
  <FCParamGroup Name="Root">
    <FCParamGroup Name="BaseApp">
      <FCParamGroup Name="Preferences">
        <FCParamGroup Name="General">
          <FCText Name="AutoloadModule">PartWorkbench</FCText>
          <FCBool Name="CheckOpenFileAtStartUp" v="0"/>
        </FCParamGroup>
        <FCParamGroup Name="Mod">
          <FCParamGroup Name="Start">
            <FCBool Name="ShowOnStartup" v="0"/>
            <FCBool Name="AllowOpenFileAtStartup" v="0"/>
          </FCParamGroup>
        </FCParamGroup>
        <FCParamGroup Name="MainWindow">
          <FCBool Name="Maximized" v="1"/>
        </FCParamGroup>
      </FCParamGroup>
    </FCParamGroup>
  </FCParamGroup>
</FCParameters>
XMLEOF

chown -R ga:ga /home/ga/.FreeCAD
chown -R ga:ga /home/ga/.config/FreeCAD

# ============================================================
# Create workspace directory
# ============================================================
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# ============================================================
# Copy real FreeCAD model files from mounted data directory
#
# T8_housing_bracket.FCStd: Real T8 lead screw housing bracket from
#   FreeCAD-library (github.com/FreeCAD/FreeCAD-library).
#   Used by export_to_stl task.
#
# contact_blocks.FCStd: Real FEM contact mechanics test geometry from
#   FreeCAD's own test suite (constraint_contact_solid_solid.FCStd
#   from freecad/Mod/Fem/femtest/), with FEM analysis objects hidden
#   and only the two solid bodies (TopBox, BottomBox) visible.
#   Used by fuse_shapes task.
# ============================================================
mkdir -p /opt/freecad_samples

echo "Copying real FreeCAD data files..."

# T8 housing bracket (real mechanical part from FreeCAD-library)
if [ -f /workspace/data/T8_housing_bracket.FCStd ]; then
    cp /workspace/data/T8_housing_bracket.FCStd /opt/freecad_samples/T8_housing_bracket.FCStd
    echo "T8_housing_bracket.FCStd: $(stat -c%s /opt/freecad_samples/T8_housing_bracket.FCStd) bytes"
else
    echo "ERROR: T8_housing_bracket.FCStd not found in /workspace/data/"
    exit 1
fi

# Contact blocks (real FEM geometry: two steel blocks in contact)
if [ -f /workspace/data/contact_blocks.FCStd ]; then
    cp /workspace/data/contact_blocks.FCStd /opt/freecad_samples/contact_blocks.FCStd
    echo "contact_blocks.FCStd: $(stat -c%s /opt/freecad_samples/contact_blocks.FCStd) bytes"
else
    echo "ERROR: contact_blocks.FCStd not found in /workspace/data/"
    exit 1
fi

# Copy to user workspace for easy access
cp /opt/freecad_samples/T8_housing_bracket.FCStd /home/ga/Documents/FreeCAD/
cp /opt/freecad_samples/contact_blocks.FCStd /home/ga/Documents/FreeCAD/
chown -R ga:ga /home/ga/Documents/FreeCAD

# Verify FreeCAD is installed and working
if which freecad > /dev/null 2>&1; then
    echo "FreeCAD found at: $(which freecad)"
else
    echo "ERROR: freecad not found in PATH"
    exit 1
fi

echo "=== FreeCAD setup complete ==="
