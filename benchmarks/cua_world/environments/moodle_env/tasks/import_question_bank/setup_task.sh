#!/bin/bash
# Setup script for Import Question Bank task

echo "=== Setting up Import Question Bank Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions in case sourcing fails or functions missing
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
    wait_for_window() {
        local window_pattern="$1"
        local timeout=${2:-30}
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then return 0; fi
            sleep 1; elapsed=$((elapsed + 1))
        done
        return 1
    }
    get_firefox_window_id() { DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'; }
    focus_window() { DISPLAY=:1 wmctrl -ia "$1" 2>/dev/null || true; sleep 0.3; }
fi

# 1. Create the GIFT file
echo "Creating GIFT file at /home/ga/Documents/pharmacology_questions.gift..."
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/pharmacology_questions.gift << 'EOF'
// Pharmacology Module 3 - Drug Classifications and Mechanisms

::Penicillin Mechanism::What is the primary mechanism of action of penicillin antibiotics?{
=Inhibition of bacterial cell wall synthesis
~Disruption of cell membrane permeability
~Inhibition of protein synthesis at the 30S ribosomal subunit
~Inhibition of DNA gyrase
}

::Beta-Blocker Target::Beta-adrenergic blocking agents primarily act on which receptor type?{
=Beta-adrenergic receptors
~Alpha-adrenergic receptors
~Muscarinic cholinergic receptors
~Dopaminergic receptors
}

::Warfarin Antidote::What is the appropriate antidote for warfarin toxicity?{
=Vitamin K (phytonadione)
~Protamine sulfate
~Naloxone
~Flumazenil
}

::ACE Inhibitor Side Effect::Which side effect is most commonly associated with ACE inhibitors?{
=Persistent dry cough
~Hyperkalemia leading to cardiac arrest
~Severe hepatotoxicity
~Ototoxicity
}

::Insulin Storage::How should unopened insulin vials be stored?{
=Refrigerated at 2-8°C (36-46°F)
~At room temperature indefinitely
~Frozen at -20°C
~In a warm dark cabinet
}

::Digoxin Toxicity Sign::Which finding is an early sign of digoxin toxicity?{
=Nausea and visual disturbances (yellow-green halos)
~Hypertension
~Tachycardia above 120 bpm
~Polyuria
}

::Nitroglycerin Administration::What is the correct initial route of administration for acute angina relief with nitroglycerin?{
=Sublingual
~Intravenous
~Intramuscular
~Oral (swallowed)
}

::Heparin Monitoring::Which laboratory test is used to monitor the therapeutic effect of unfractionated heparin?{
=Activated partial thromboplastin time (aPTT)
~Prothrombin time (PT/INR)
~Complete blood count (CBC)
~Serum creatinine
}
EOF

# Verify file creation
if [ -f "/home/ga/Documents/pharmacology_questions.gift" ]; then
    echo "GIFT file created successfully."
else
    echo "ERROR: Failed to create GIFT file."
    exit 1
fi
chmod 644 /home/ga/Documents/pharmacology_questions.gift
chown ga:ga /home/ga/Documents/pharmacology_questions.gift

# 2. Record initial state (Course ID and Question Count)
# Get BIO101 course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: BIO101 course not found!"
    # Try to continue cleanly or exit? Better to exit as task is impossible
    exit 1
fi
echo "BIO101 Course ID: $COURSE_ID"

# Record initial total question count in the system (simplest baseline)
INITIAL_TOTAL_QUESTIONS=$(moodle_query "SELECT COUNT(*) FROM mdl_question" | tr -d '[:space:]')
echo "$INITIAL_TOTAL_QUESTIONS" > /tmp/initial_question_count
echo "Initial total questions: $INITIAL_TOTAL_QUESTIONS"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# 3. Ensure Firefox is running
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="