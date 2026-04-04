#!/bin/bash
# Export result for Web Accessibility Audit task
# Queries browser history for ssa.gov and irs.gov visits,
# reads the audit report file, and exports a result JSON for verification.

set -e

TASK_NAME="web_accessibility_audit"
RESULT_PATH="/tmp/${TASK_NAME}_result.json"
REPORT_FILE="/home/ga/Desktop/accessibility_audit_report.txt"
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
BASELINE_FILE="/tmp/task_baseline_${TASK_NAME}.json"

echo "=== Exporting result for ${TASK_NAME} ==="

# Read task start timestamp
TASK_START=0
if [ -f "${START_TS_FILE}" ]; then
    TASK_START=$(cat "${START_TS_FILE}" | tr -d '[:space:]')
fi
echo "Task start timestamp: ${TASK_START}"

python3 << PYEOF
import sqlite3, shutil, json, os, re, sys

task_start = ${TASK_START}
history_src = "/home/ga/.config/microsoft-edge/Default/History"
history_tmp = "/tmp/task_export_history_wa.sqlite"
baseline_path = "/tmp/task_baseline_web_accessibility_audit.json"
report_path   = "/home/ga/Desktop/accessibility_audit_report.txt"
result_path   = "/tmp/web_accessibility_audit_result.json"

# ── Load baseline ─────────────────────────────────────────────────────────────
baseline = {"ssa_count": 0, "irs_count": 0, "ssa_pages": [], "irs_pages": []}
if os.path.exists(baseline_path):
    try:
        with open(baseline_path) as f:
            baseline = json.load(f)
    except Exception:
        pass

# ── Query current history ─────────────────────────────────────────────────────
history_data = {
    "ssa_new": False,
    "irs_new": False,
    "ssa_pages_visited": 0,
    "irs_pages_visited": 0,
    "ssa_urls": [],
    "irs_urls": [],
}

if os.path.exists(history_src):
    try:
        shutil.copy2(history_src, history_tmp)
        conn = sqlite3.connect(history_tmp)
        cur = conn.cursor()

        # Count ssa.gov visits added after task start
        cur.execute("""
            SELECT url, visit_count, last_visit_time
            FROM urls
            WHERE url LIKE '%ssa.gov%'
        """)
        ssa_rows = cur.fetchall()
        # Chrome timestamps are microseconds since 1601-01-01; convert to Unix
        # Unix epoch offset from 1601 in microseconds: 11644473600 * 1000000
        CHROME_EPOCH_OFFSET = 11644473600 * 1_000_000
        ssa_new_urls = []
        for url, vcount, lvt in ssa_rows:
            unix_ts = (lvt - CHROME_EPOCH_OFFSET) // 1_000_000 if lvt else 0
            if unix_ts > task_start:
                ssa_new_urls.append(url)

        # Count irs.gov visits added after task start
        cur.execute("""
            SELECT url, visit_count, last_visit_time
            FROM urls
            WHERE url LIKE '%irs.gov%'
        """)
        irs_rows = cur.fetchall()
        irs_new_urls = []
        for url, vcount, lvt in irs_rows:
            unix_ts = (lvt - CHROME_EPOCH_OFFSET) // 1_000_000 if lvt else 0
            if unix_ts > task_start:
                irs_new_urls.append(url)

        conn.close()
        os.remove(history_tmp)

        history_data["ssa_new"] = len(ssa_new_urls) > 0
        history_data["irs_new"] = len(irs_new_urls) > 0
        history_data["ssa_pages_visited"] = len(ssa_new_urls)
        history_data["irs_pages_visited"] = len(irs_new_urls)
        history_data["ssa_urls"] = ssa_new_urls[:10]
        history_data["irs_urls"] = irs_new_urls[:10]

    except Exception as e:
        print(f"Warning: history query failed: {e}", file=sys.stderr)

# ── Analyze report file ────────────────────────────────────────────────────────
ACCESSIBILITY_VOCAB = [
    "wcag", "aria", "alt text", "alt-text", "contrast", "keyboard",
    "screen reader", "screenreader", "focus", "tab order", "tabindex",
    "landmark", "heading", "label", "accessible", "accessibility",
    "section 508", "508", "lighthouse", "audit", "violation", "criterion",
    "success criterion", "perceivable", "operable", "understandable",
    "robust", "a11y", "color blind", "colorblind", "form element",
    "skip link", "skip navigation", "role attribute", "semantic"
]

SEVERITY_TERMS = ["critical", "serious", "moderate", "minor", "low", "high", "medium"]

report_data = {
    "exists": False,
    "modified_after_start": False,
    "char_count": 0,
    "mentions_ssa": False,
    "mentions_irs": False,
    "has_accessibility_vocab": False,
    "vocab_found": [],
    "has_lighthouse_score": False,
    "has_severity_classification": False,
    "severity_terms_found": [],
}

if os.path.exists(report_path):
    fi = os.stat(report_path)
    mtime = int(fi.st_mtime)
    report_data["exists"] = True
    report_data["modified_after_start"] = mtime > task_start
    try:
        with open(report_path, "r", errors="replace") as f:
            content = f.read()
        report_data["char_count"] = len(content)
        content_lower = content.lower()

        # Check site mentions
        report_data["mentions_ssa"] = (
            "ssa.gov" in content_lower or "social security" in content_lower
        )
        report_data["mentions_irs"] = (
            "irs.gov" in content_lower or "internal revenue" in content_lower
        )

        # Check accessibility vocabulary
        found_vocab = [v for v in ACCESSIBILITY_VOCAB if v in content_lower]
        report_data["vocab_found"] = found_vocab
        report_data["has_accessibility_vocab"] = len(found_vocab) >= 4

        # Check for Lighthouse scores (numeric score like "87" or "92" near "score"/"lighthouse")
        score_patterns = [
            r'lighthouse[^\n]*?(\d{2,3})',
            r'(\d{2,3})[^\n]*?score',
            r'score[^\n]*?(\d{2,3})',
            r'accessibility[^\n]*?(\d{2,3})',
            r'(\d{2,3})[^\n]*?accessibility',
        ]
        has_score = any(re.search(p, content_lower) for p in score_patterns)
        report_data["has_lighthouse_score"] = has_score

        # Check severity classification
        found_severity = [t for t in SEVERITY_TERMS if t in content_lower]
        report_data["severity_terms_found"] = found_severity
        report_data["has_severity_classification"] = len(found_severity) >= 1

    except Exception as e:
        print(f"Warning: could not read report: {e}", file=sys.stderr)

# ── Assemble final result ──────────────────────────────────────────────────────
result = {
    "task": "web_accessibility_audit",
    "task_start": task_start,
    "history": history_data,
    "report": report_data,
}

with open(result_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result written to {result_path}")
print(f"  ssa.gov new visits: {history_data['ssa_pages_visited']}")
print(f"  irs.gov new visits: {history_data['irs_pages_visited']}")
print(f"  Report exists: {report_data['exists']}, modified_after_start: {report_data['modified_after_start']}")
print(f"  Report chars: {report_data['char_count']}")
print(f"  Vocab found ({len(report_data['vocab_found'])}): {report_data['vocab_found'][:8]}")
print(f"  Lighthouse score detected: {report_data['has_lighthouse_score']}")
print(f"  Severity terms: {report_data['severity_terms_found']}")
PYEOF

echo "=== Export complete for ${TASK_NAME} ==="
