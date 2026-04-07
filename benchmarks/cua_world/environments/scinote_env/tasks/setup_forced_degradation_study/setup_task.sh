#!/bin/bash
echo "=== Setting up setup_forced_degradation_study task ==="

# Clean up previous task files BEFORE recording timestamp
rm -f /tmp/forced_degradation_result.json 2>/dev/null || true
rm -f /tmp/forced_degradation_initial_counts.json 2>/dev/null || true
rm -f /tmp/task_start_time.txt 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Record baseline counts (agent starts from blank state)
INITIAL_PROJECT_COUNT=$(get_project_count)
INITIAL_EXP_COUNT=$(get_experiment_count)
INITIAL_TASK_COUNT=$(get_my_module_count)
INITIAL_REPO_COUNT=$(get_repository_count)

safe_write_json "/tmp/forced_degradation_initial_counts.json" "{\"projects\": ${INITIAL_PROJECT_COUNT:-0}, \"experiments\": ${INITIAL_EXP_COUNT:-0}, \"tasks\": ${INITIAL_TASK_COUNT:-0}, \"repositories\": ${INITIAL_REPO_COUNT:-0}}"
echo "Baseline: projects=${INITIAL_PROJECT_COUNT}, experiments=${INITIAL_EXP_COUNT}, tasks=${INITIAL_TASK_COUNT}, repos=${INITIAL_REPO_COUNT}"

# ---- Place protocol file on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/degradation_protocol.txt << 'PROTOCOL_EOF'
Forced Degradation Procedure - ICH Q1A Guidelines
Product: Ibuprofen Tablets 200mg

1. Stock Solution Preparation
Weigh 50.0 mg Ibuprofen Reference Standard into a 50 mL volumetric flask.
Dissolve in 30 mL HPLC-grade acetonitrile with 5 min sonication. Dilute
to volume to obtain 1.0 mg/mL stock. Verify complete dissolution visually.

2. Acid Hydrolysis Sample
Transfer 5.0 mL stock to a 25 mL flask. Add 5.0 mL 0.1M HCl. Heat at
80 degrees C for 4 hours. Cool, neutralize with 5.0 mL 0.1M NaOH, dilute to
volume with mobile phase (acetonitrile:0.1% H3PO4, 60:40 v/v).

3. Base Hydrolysis Sample
Transfer 5.0 mL stock to a 25 mL flask. Add 5.0 mL 0.1M NaOH. Heat at
80 degrees C for 4 hours. Cool, neutralize with 5.0 mL 0.1M HCl, dilute to
volume with mobile phase.

4. Oxidative Degradation Sample
Transfer 5.0 mL stock to a 25 mL flask. Add 5.0 mL of 3% hydrogen
peroxide. Store at room temperature protected from light for 24 hours.
Dilute to volume with mobile phase.

5. Control Sample
Transfer 5.0 mL stock to a 25 mL flask. Dilute directly to volume with
mobile phase. This serves as the unstressed t=0 reference.

6. HPLC Analysis Parameters
Column: C18, 250 x 4.6 mm, 5 um. Mobile phase: ACN:0.1% H3PO4 (60:40).
Flow: 1.0 mL/min. Injection: 20 uL. Detection: UV 221 nm. Run time:
15 min. Column temp: 30 degrees C. Ibuprofen RT: approximately 7.8 min.
PROTOCOL_EOF

chown ga:ga /home/ga/Desktop/degradation_protocol.txt
chmod 644 /home/ga/Desktop/degradation_protocol.txt

# ---- Place HPLC summary file on Desktop ----
cat > /home/ga/Desktop/hplc_summary.txt << 'SUMMARY_EOF'
HPLC Forced Degradation Results - Ibuprofen

Control: 99.8% purity, no significant degradants detected.
Acid hydrolysis (0.1M HCl, 80C, 4h): 84.7% purity, 9.2% main degradant.
Base hydrolysis (0.1M NaOH, 80C, 4h): 89.2% purity, 6.5% main degradant.
Oxidative stress (3% H2O2, RT, 48h): 80.2% purity, 12.1% main degradant.

Conclusion: Ibuprofen is most susceptible to oxidative degradation.
All conditions produced greater than 10% degradation, confirming method specificity.
SUMMARY_EOF

chown ga:ga /home/ga/Desktop/hplc_summary.txt
chmod 644 /home/ga/Desktop/hplc_summary.txt

# ---- Ensure Firefox is running at the SciNote login page ----
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/forced_degradation_start_screenshot.png

echo "=== Setup complete. Agent must create full forced degradation study documentation. ==="
echo "Files placed: ~/Desktop/degradation_protocol.txt, ~/Desktop/hplc_summary.txt"
