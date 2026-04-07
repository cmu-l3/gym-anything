#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Debug HL7 Anonymizer Result ==="

WORKSPACE_DIR="/home/ga/workspace/hl7_anonymizer"
RESULT_FILE="/tmp/hl7_anonymizer_result.json"

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1

# Remove any stale result file
rm -f "$RESULT_FILE"

# ─────────────────────────────────────────────────────────────
# 1. Run Hidden Behavioral Tests (Directly evaluating exported modules)
# ─────────────────────────────────────────────────────────────
cat > /tmp/evaluate_hl7.js << 'EOF'
const fs = require('fs');
const path = require('path');

let results = {
    al1_crash_fixed: false,
    obx_filter_fixed: false,
    phi_redacted: false,
    date_fixed: false,
    parser_error: null,
    date_error: null
};

try {
    const workspace = '/home/ga/workspace/hl7_anonymizer';
    const parser = require(path.join(workspace, 'src/parser'));
    const anonymizer = require(path.join(workspace, 'src/anonymizer'));
    const { shiftDate } = require(path.join(workspace, 'src/utils/dateFormatter'));

    // Test Parser & Anonymizer
    try {
        const raw = "PID|1||123||Smith^John||19900531||||123 Main St||555-1234\nOBX|1|NM|WBC||5.5|K/uL\nOBX|2|NM|RBC||4.5|M/uL";
        
        // This will crash if AL1 check is missing
        const parsed = parser.parse(raw);
        results.al1_crash_fixed = true; 

        if (parsed.labs && parsed.labs.length === 2) {
            results.obx_filter_fixed = true;
        }

        const anon = anonymizer.anonymize(parsed);
        if (anon && anon.patient) {
            const hasAddress = anon.patient.address !== undefined;
            const hasPhone = anon.patient.phone !== undefined;
            if (!hasAddress && !hasPhone) {
                results.phi_redacted = true;
            }
        }
    } catch(e) {
        results.parser_error = e.toString();
    }

    // Test Date Formatter
    try {
        const shifted = shiftDate("19900531", -15);
        if (shifted === "19900516") {
            results.date_fixed = true;
        }
    } catch(e) {
        results.date_error = e.toString();
    }
} catch(e) {
    results.global_error = e.toString();
}

fs.writeFileSync('/tmp/eval_behavior.json', JSON.stringify(results, null, 2));
EOF

sudo -u ga node /tmp/evaluate_hl7.js || echo '{"error": "node script failed"}' > /tmp/eval_behavior.json

# ─────────────────────────────────────────────────────────────
# 2. Package everything into a single export JSON
# ─────────────────────────────────────────────────────────────
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"

try:
    with open('/tmp/eval_behavior.json', 'r') as f:
        eval_behavior = json.load(f)
except Exception as e:
    eval_behavior = {"error": str(e)}

files_to_export = {
    "src/index.js":                  os.path.join(workspace, "src", "index.js"),
    "src/parser.js":                 os.path.join(workspace, "src", "parser.js"),
    "src/anonymizer.js":             os.path.join(workspace, "src", "anonymizer.js"),
    "src/utils/dateFormatter.js":    os.path.join(workspace, "src", "utils", "dateFormatter.js")
}

source_files = {}
for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            source_files[label] = f.read()
    except Exception as e:
        source_files[label] = None
        print(f"Warning: error reading {path}: {e}")

result_data = {
    "eval_behavior": eval_behavior,
    "source_files": source_files
}

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result_data, out, indent=2)

print(f"Exported files to $RESULT_FILE")
PYEXPORT

echo "=== Export Complete ==="