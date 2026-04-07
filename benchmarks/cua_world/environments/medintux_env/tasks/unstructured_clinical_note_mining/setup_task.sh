#!/bin/bash
set -e
echo "=== Setting up Unstructured Clinical Note Mining Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Start MySQL and MedinTux dependencies
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# 2. Prepare the database environment
echo "Preparing clinical data..."

# Create a simulation table for unstructured notes if it doesn't exist
# We use a custom table to avoid corrupting the complex RTF/Blob format of real MedinTux Rubriques
mysql -u root DrTuxTest << 'EOF'
DROP TABLE IF EXISTS Legacy_Observations;
CREATE TABLE Legacy_Observations (
    obs_id INT AUTO_INCREMENT PRIMARY KEY,
    patient_guid VARCHAR(128),
    note_date DATE,
    note_text TEXT,
    INDEX (patient_guid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
EOF

# 3. Select random patients to be our "Cases"
# We need about 10 patients to inject notes for.
# We'll get their GUIDs and Names.
echo "Selecting patients for data injection..."
ALL_PATIENTS=$(mysql -u root DrTuxTest -N -e "SELECT FchPat_GUID_Doss FROM fchpat ORDER BY RAND() LIMIT 10")

# Counters
COUNT=0
TRUE_POSITIVES=""

# 4. Inject specific scenarios
for guid in $ALL_PATIENTS; do
    COUNT=$((COUNT+1))
    
    # Generate a random date
    R_YEAR=$((2010 + RANDOM % 14))
    R_MONTH=$((1 + RANDOM % 12))
    R_DAY=$((1 + RANDOM % 28))
    NOTE_DATE="$R_YEAR-$R_MONTH-$R_DAY"

    case $COUNT in
        1)
            # CASE 1: Standard spelling with accent (Positive)
            TEXT="Patient signale une allergie à la Pénicilline depuis l'enfance."
            TRUE_POSITIVES="$TRUE_POSITIVES $guid"
            ;;
        2)
            # CASE 2: Uppercase, no accent (Positive)
            TEXT="CHOC ANAPHYLACTIQUE SOUS PENICILLINE EN 2015. STRICTEMENT INTERDIT."
            TRUE_POSITIVES="$TRUE_POSITIVES $guid"
            ;;
        3)
            # CASE 3: Lowercase, no accent (Positive)
            TEXT="Intolérance digestive sévère à la penicilline, à éviter si possible."
            TRUE_POSITIVES="$TRUE_POSITIVES $guid"
            ;;
        4)
            # CASE 4: Negative Control (No mention)
            TEXT="Pas d'antécédents chirurgicaux. Vaccination à jour."
            ;;
        5)
            # CASE 5: Distractor (Amoxicilline - related but not the exact word, task asks for 'pénicilline')
            # Actually, Amoxicillin IS a penicillin, but usually SQL tasks look for the string.
            # To be safe and unambiguous for the agent, we'll use a totally different drug.
            TEXT="Allergie aux Sulfamides rapportée par le patient."
            ;;
        6)
            # CASE 6: Embedded in long text (Positive)
            TEXT="Consultation de routine. TA 12/7. Le patient demande un certificat. Note: Allergie penicilline à vérifier."
            TRUE_POSITIVES="$TRUE_POSITIVES $guid"
            ;;
        *)
            # Filler
            TEXT="RAS. Examen cardio-pulmonaire normal."
            ;;
    esac

    # Escape single quotes for SQL
    SAFE_TEXT=$(echo "$TEXT" | sed "s/'/\\\'/g")
    
    # Insert into Legacy_Observations
    mysql -u root DrTuxTest -e "INSERT INTO Legacy_Observations (patient_guid, note_date, note_text) VALUES ('$guid', '$NOTE_DATE', '$SAFE_TEXT');"
done

# 5. Save Ground Truth (Hidden from agent)
echo "$TRUE_POSITIVES" | tr ' ' '\n' | grep -v "^$" | sort > /tmp/ground_truth_ids.txt
chmod 600 /tmp/ground_truth_ids.txt

echo "Injected $(wc -l < /tmp/ground_truth_ids.txt) positive cases."

# 6. Ensure MedinTux Manager is running (standard context)
launch_medintux_manager

# 7. Record start time
date +%s > /tmp/task_start_time.txt

# 8. Clear previous results
rm -f /home/ga/Documents/penicillin_safety_review.csv

# 9. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="