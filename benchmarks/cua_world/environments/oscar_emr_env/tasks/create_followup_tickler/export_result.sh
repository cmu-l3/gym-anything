#!/bin/bash
# Export script for Create Followup Tickler task in OSCAR EMR

echo "=== Exporting Create Followup Tickler Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

PATIENT_NO=$(cat /tmp/task_patient_no_tickler 2>/dev/null || oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Thomas' AND last_name='Bergmann' LIMIT 1")
INITIAL_NOTE_COUNT=$(cat /tmp/initial_note_count_tickler 2>/dev/null || echo "0")
INITIAL_TICKLER_COUNT=$(cat /tmp/initial_tickler_count 2>/dev/null || echo "0")

echo "Patient demographic_no: $PATIENT_NO"

python3 << PYEOF
import json, subprocess

patient_no = "${PATIENT_NO}"
initial_notes = int("${INITIAL_NOTE_COUNT}".strip() or "0")
initial_ticklers = int("${INITIAL_TICKLER_COUNT}".strip() or "0")

def run_query(q):
    try:
        r = subprocess.run(
            ['docker', 'exec', 'oscar-db', 'mysql', '-u', 'oscar', '-poscar', 'oscar', '-N', '-e', q],
            capture_output=True, text=True, timeout=15
        )
        return r.stdout.strip()
    except Exception:
        return ""

# Query encounter notes
current_notes = int(run_query(f"SELECT COUNT(*) FROM casemgmt_note WHERE demographic_no={patient_no} AND archived=0") or "0")
latest_note = run_query(f"SELECT LEFT(note, 800) FROM casemgmt_note WHERE demographic_no={patient_no} AND archived=0 ORDER BY note_id DESC LIMIT 1")

# Query ticklers
current_ticklers = int(run_query(f"SELECT COUNT(*) FROM tickler WHERE demographic_no={patient_no}") or "0")
latest_tickler_msg = run_query(f"SELECT message FROM tickler WHERE demographic_no={patient_no} ORDER BY tickler_no DESC LIMIT 1")
all_tickler_msgs = run_query(f"SELECT message FROM tickler WHERE demographic_no={patient_no} ORDER BY tickler_no DESC")

# Analyze note content
note_lower = latest_note.lower()
note_has_chest_pain = any(kw in note_lower for kw in ['chest pain', 'chest discomfort', 'chest', 'angina'])
note_has_ecg = any(kw in note_lower for kw in ['ecg', 'ekg', 'electrocardiogram', 'st change', 'st elevation', 'st depression'])
note_has_cardiology = any(kw in note_lower for kw in ['cardiol', 'cardiolog', 'referr'])
note_has_content = len(latest_note.strip()) > 50

# Analyze tickler content
tickler_lower = latest_tickler_msg.lower() if latest_tickler_msg else ''
tickler_has_cardiology = any(kw in tickler_lower for kw in ['cardiol', 'referral', 'cardio'])
tickler_has_followup = any(kw in tickler_lower for kw in ['follow', 'contact', 'appointment', 'call', '2 week', 'two week'])
tickler_has_content = len(latest_tickler_msg.strip()) > 10 if latest_tickler_msg else False

result = {
    "patient_no": patient_no,
    "patient_fname": "Thomas",
    "patient_lname": "Bergmann",
    "initial_note_count": initial_notes,
    "current_note_count": current_notes,
    "new_note_count": current_notes - initial_notes,
    "latest_note_excerpt": latest_note[:400] if latest_note else "",
    "note_has_chest_pain": note_has_chest_pain,
    "note_has_ecg_mention": note_has_ecg,
    "note_has_cardiology": note_has_cardiology,
    "note_has_content": note_has_content,
    "initial_tickler_count": initial_ticklers,
    "current_tickler_count": current_ticklers,
    "new_tickler_count": current_ticklers - initial_ticklers,
    "latest_tickler_message": latest_tickler_msg[:300] if latest_tickler_msg else "",
    "tickler_has_cardiology": tickler_has_cardiology,
    "tickler_has_followup": tickler_has_followup,
    "tickler_has_content": tickler_has_content,
    "export_timestamp": __import__('datetime').datetime.now().isoformat()
}

with open('/tmp/create_followup_tickler_result.json', 'w') as f:
    json.dump(result, f, indent=2)

new_notes = current_notes - initial_notes
new_ticklers = current_ticklers - initial_ticklers
print(f"Export: {new_notes} new notes (chest_pain={note_has_chest_pain}, ecg={note_has_ecg})")
print(f"        {new_ticklers} new ticklers (cardiology={tickler_has_cardiology})")
PYEOF

echo "Result saved to /tmp/create_followup_tickler_result.json"
echo "=== Export Complete ==="
