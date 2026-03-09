#!/bin/bash
set -e
echo "=== Setting up fix_xml_config_errors task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Define paths
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_NAME="RadOncPhysics"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous attempts
rm -rf "$PROJECT_DIR"
# Note: We don't wipe the whole workspace metadata to avoid killing Eclipse state, 
# but ensuring the folder is new means it won't be in the Package Explorer if Eclipse is already running.

# 2. Create Project Directory
su - ga -c "mkdir -p '$PROJECT_DIR'"

# 3. Create .project file (standard Eclipse project)
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>RadOncPhysics</name>
	<comment></comment>
	<projects>
	</projects>
	<buildSpec>
	</buildSpec>
	<natures>
	</natures>
</projectDescription>
EOF

# 4. Create XSD Schema
cat > "$PROJECT_DIR/beam_schema.xsd" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
    <xs:element name="BeamModel">
        <xs:complexType>
            <xs:sequence>
                <xs:element name="MachineName" type="xs:string"/>
                <xs:element name="RadiationType">
                    <xs:simpleType>
                        <xs:restriction base="xs:string">
                            <xs:enumeration value="Photon"/>
                            <xs:enumeration value="Electron"/>
                        </xs:restriction>
                    </xs:simpleType>
                </xs:element>
                <xs:element name="NominalEnergy" type="xs:string"/>
                <xs:element name="ReferenceDoseRate" type="xs:integer"/>
                <xs:element name="DepthDoseParams">
                    <xs:complexType>
                        <xs:sequence>
                            <xs:element name="Dmax" type="xs:decimal"/>
                            <xs:element name="PddAt10" type="xs:decimal"/>
                            <xs:element name="SurfaceDose" type="xs:decimal" minOccurs="0"/>
                        </xs:sequence>
                    </xs:complexType>
                </xs:element>
            </xs:sequence>
        </xs:complexType>
    </xs:element>
</xs:schema>
EOF

# 5. Create Broken XML
# Contains 3 errors: Proton (enum), SixHundred (type), Missing Dmax (structure)
cat > "$PROJECT_DIR/beam_model.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<BeamModel xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="beam_schema.xsd">
    <MachineName>Varian TrueBeam 1234</MachineName>
    <RadiationType>Proton</RadiationType>
    <NominalEnergy>6MV</NominalEnergy>
    <ReferenceDoseRate>SixHundred</ReferenceDoseRate>
    <DepthDoseParams>
        <PddAt10>67.5</PddAt10>
        <SurfaceDose>0.45</SurfaceDose>
    </DepthDoseParams>
</BeamModel>
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# 6. Ensure Eclipse is running and ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Focus and maximize
focus_eclipse_window
sleep 2

# Dismiss any dialogs
dismiss_dialogs 3

# Close welcome tab if present
close_welcome_tab

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Project created at $PROJECT_DIR"
echo "Eclipse is running, waiting for agent to import project."