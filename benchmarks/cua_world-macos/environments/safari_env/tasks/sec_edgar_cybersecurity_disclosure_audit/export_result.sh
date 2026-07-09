#!/usr/bin/env bash
set -euo pipefail

RESULT_FILE="/tmp/edgar_cybersecurity_audit_result.json"
REPORT_FILE="/Users/lume/Documents/edgar_cybersecurity_audit.json"
HISTORY_DB="/Users/lume/Library/Safari/History.db"

# ── Task-start timestamp ──────────────────────────────────────────────────────
TASK_START=$(cat /tmp/edgar_task_start_timestamp 2>/dev/null || echo "0")
# Convert Unix epoch → Mac absolute time (seconds since 2001-01-01)
MAC_START=$((TASK_START - 978307200))

# ── Quit Safari + flush WAL so History.db is readable ────────────────────────
osascript -e 'tell application "Safari" to quit' 2>/dev/null || true
pkill -x Safari 2>/dev/null || true
sleep 2
sqlite3 "$HISTORY_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
sleep 1

# ── History.db visit counts (per relevant domain) ────────────────────────────
query_visits() {
    local domain="$1"
    sqlite3 "$HISTORY_DB" \
        "SELECT COUNT(*) FROM history_items hi
         JOIN history_visits hv ON hi.id = hv.history_item
         WHERE hi.domain_expansion LIKE '%${domain}%'
           AND hv.visit_time > ${MAC_START};" 2>/dev/null || echo "0"
}

EDGAR_VISITS=$(query_visits "sec.gov")
JPM_VISITS=$(query_visits "jpmorganchase.com")
BOA_VISITS=$(query_visits "bankofamerica.com")
WELLS_VISITS=$(query_visits "wellsfargo.com")
CITI_VISITS=$(query_visits "citigroup.com")
GS_VISITS=$(query_visits "goldmansachs.com")

# ── Output file metadata ──────────────────────────────────────────────────────
REPORT_EXISTS=false
REPORT_MTIME=0
REPORT_SIZE=0
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -f %m "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -f %z "$REPORT_FILE" 2>/dev/null || echo "0")
fi

# ── Parse and analyse report JSON ────────────────────────────────────────────
python3 << 'PYEOF'
import json, os, sys

REPORT_PATH = "/Users/lume/Documents/edgar_cybersecurity_audit.json"
TASK_START  = int(open("/tmp/edgar_task_start_timestamp").read().strip()) if os.path.exists("/tmp/edgar_task_start_timestamp") else 0
REPORT_MTIME = int(os.stat(REPORT_PATH).st_mtime) if os.path.exists(REPORT_PATH) else 0

REQUIRED_BANKS = [
    "JPMorgan Chase", "Bank of America", "Wells Fargo", "Citigroup", "Goldman Sachs"
]
BANK_KEYWORDS = {
    "JPMorgan Chase":  ["jpmorgan", "chase", "jpmorganchase"],
    "Bank of America": ["bank of america", "bankofamerica", "bofa"],
    "Wells Fargo":     ["wells fargo", "wellsfargo"],
    "Citigroup":       ["citigroup", "citi"],
    "Goldman Sachs":   ["goldman sachs", "goldmansachs"],
}
CYBER_KEYWORDS = [
    "cybersecurity", "cyber security", "cyber risk", "cyber attack",
    "data breach", "information security", "data security", "ransomware",
    "malware", "phishing", "technology risk", "operational risk",
]

analysis = {
    "report_exists": False,
    "report_written_after_start": False,
    "banks_found": [],
    "banks_complete": [],
    "bank_details": {},
    "parse_error": None,
}

try:
    if not os.path.exists(REPORT_PATH):
        raise FileNotFoundError("output file missing")

    analysis["report_exists"] = True
    analysis["report_written_after_start"] = REPORT_MTIME > TASK_START

    with open(REPORT_PATH) as f:
        data = json.load(f)

    if not isinstance(data, list):
        # Accept either a list of objects or a dict keyed by bank name
        if isinstance(data, dict):
            data = list(data.values())
        else:
            raise ValueError("top-level JSON must be a list or object")

    for entry in data:
        if not isinstance(entry, dict):
            continue
        # Match entry to a known bank
        matched_bank = None
        entry_str = json.dumps(entry).lower()
        for bank, kws in BANK_KEYWORDS.items():
            if any(kw in entry_str for kw in kws):
                matched_bank = bank
                break
        if matched_bank is None:
            continue
        if matched_bank in analysis["banks_found"]:
            continue
        analysis["banks_found"].append(matched_bank)

        # Check required fields
        has_cik           = bool(entry.get("cik"))
        has_company_name  = bool(entry.get("company_name"))
        has_fiscal_year   = bool(entry.get("fiscal_year_end"))
        has_filing_date   = bool(entry.get("filing_date"))
        excerpt           = entry.get("cybersecurity_risk_factor_excerpt", "") or ""
        excerpt_words     = len(excerpt.split())
        has_long_excerpt  = excerpt_words >= 100
        is_cyber_excerpt  = any(kw in excerpt.lower() for kw in CYBER_KEYWORDS)

        detail = {
            "has_cik":          has_cik,
            "has_company_name": has_company_name,
            "has_fiscal_year":  has_fiscal_year,
            "has_filing_date":  has_filing_date,
            "excerpt_words":    excerpt_words,
            "has_long_excerpt": has_long_excerpt,
            "is_cyber_excerpt": is_cyber_excerpt,
        }
        analysis["bank_details"][matched_bank] = detail

        complete = (has_cik and has_company_name and has_fiscal_year
                    and has_filing_date and has_long_excerpt and is_cyber_excerpt)
        if complete:
            analysis["banks_complete"].append(matched_bank)

except Exception as e:
    analysis["parse_error"] = str(e)

with open("/tmp/_edgar_analysis.json", "w") as f:
    json.dump(analysis, f)
PYEOF

# ── Read python analysis ──────────────────────────────────────────────────────
ANALYSIS=$(cat /tmp/_edgar_analysis.json 2>/dev/null || echo '{}')
rm -f /tmp/_edgar_analysis.json

# ── Assemble final result JSON ────────────────────────────────────────────────
python3 << PYEOF
import json

analysis     = json.loads("""${ANALYSIS}""")
edgar_visits = int("${EDGAR_VISITS}" or 0)
jpm_visits   = int("${JPM_VISITS}"   or 0)
boa_visits   = int("${BOA_VISITS}"   or 0)
wells_visits = int("${WELLS_VISITS}" or 0)
citi_visits  = int("${CITI_VISITS}"  or 0)
gs_visits    = int("${GS_VISITS}"    or 0)
report_mtime = int("${REPORT_MTIME}" or 0)
task_start   = int("${TASK_START}"   or 0)

result = {
    "history": {
        "edgar_visits":  edgar_visits,
        "jpm_visits":    jpm_visits,
        "boa_visits":    boa_visits,
        "wells_visits":  wells_visits,
        "citi_visits":   citi_visits,
        "gs_visits":     gs_visits,
    },
    "report_exists":              analysis.get("report_exists", False),
    "report_written_after_start": analysis.get("report_written_after_start", False),
    "banks_found":                analysis.get("banks_found", []),
    "banks_complete":             analysis.get("banks_complete", []),
    "bank_details":               analysis.get("bank_details", {}),
    "parse_error":                analysis.get("parse_error"),
    "report_size_bytes":          int("${REPORT_SIZE}" or 0),
}

with open("${RESULT_FILE}", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "export complete → ${RESULT_FILE}"
