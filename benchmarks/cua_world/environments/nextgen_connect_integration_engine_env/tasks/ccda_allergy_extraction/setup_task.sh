#!/bin/bash
set -e
echo "=== Setting up C-CDA Allergy Extraction Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Create Directories
echo "Creating input/output directories..."
mkdir -p /home/ga/ccda_input
mkdir -p /home/ga/allergy_output
chown -R ga:ga /home/ga/ccda_input /home/ga/allergy_output
chmod 777 /home/ga/ccda_input /home/ga/allergy_output

# 2. Create Sample C-CDA File
echo "Generating sample C-CDA file..."
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/sample_ccda.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<ClinicalDocument xmlns="urn:hl7-org:v3" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <realmCode code="US"/>
    <typeId root="2.16.840.1.113883.1.3" extension="POCD_HD000040"/>
    <recordTarget>
        <patientRole>
            <id root="2.16.840.1.113883.4.1" extension="123456789"/>
            <patient>
                <name>
                    <given>John</given>
                    <family>Doe</family>
                </name>
                <administrativeGenderCode code="M" codeSystem="2.16.840.1.113883.5.1"/>
                <birthTime value="19800101"/>
            </patient>
        </patientRole>
    </recordTarget>
    <component>
        <structuredBody>
            <!-- Allergies Section -->
            <component>
                <section>
                    <templateId root="2.16.840.1.113883.10.20.22.2.6.1"/>
                    <code code="48765-2" codeSystem="2.16.840.1.113883.6.1"/>
                    <title>Allergies and Intolerances</title>
                    <entry>
                        <act classCode="ACT" moodCode="EVN">
                            <templateId root="2.16.840.1.113883.10.20.22.4.30"/>
                            <statusCode code="active"/>
                            <entryRelationship typeCode="SUBJ">
                                <observation classCode="OBS" moodCode="EVN">
                                    <templateId root="2.16.840.1.113883.10.20.22.4.7"/>
                                    <participant typeCode="CSM">
                                        <participantRole classCode="MANU">
                                            <playingEntity classCode="MMAT">
                                                <code code="70618" codeSystem="2.16.840.1.113883.6.88" displayName="Penicillin"/>
                                                <name>Penicillin</name>
                                            </playingEntity>
                                        </participantRole>
                                    </participant>
                                    <entryRelationship typeCode="MFST" inversionInd="true">
                                        <observation classCode="OBS" moodCode="EVN">
                                            <templateId root="2.16.840.1.113883.10.20.22.4.9"/>
                                            <value xsi:type="CD" code="247472004" codeSystem="2.16.840.1.113883.6.96" displayName="Hives"/>
                                        </observation>
                                    </entryRelationship>
                                </observation>
                            </entryRelationship>
                        </act>
                    </entry>
                </section>
            </component>
        </structuredBody>
    </component>
</ClinicalDocument>
EOF

chown ga:ga /home/ga/Documents/sample_ccda.xml

# 3. Setup NextGen Connect (ensure it's running)
# Note: The environment setup script already starts it, but we wait to be safe.
echo "Waiting for NextGen Connect API..."
wait_for_api 60

# 4. Open Firefox to Landing Page
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 5
fi

# 5. Open Terminal for user convenience
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "Task: Extract Allergies from C-CDA"
echo "Input Dir: /home/ga/ccda_input"
echo "Output Dir: /home/ga/allergy_output"
echo "Sample File: /home/ga/Documents/sample_ccda.xml"
echo ""
echo "Tip: C-CDA uses XML namespaces (urn:hl7-org:v3)."
echo "In E4X, you may need: default xml namespace = \"urn:hl7-org:v3\";"
echo ""
exec bash
' 2>/dev/null &

# 6. Initial Screenshot
sleep 5
take_screenshot /tmp/task_initial.png

# 7. Record Start Time
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="