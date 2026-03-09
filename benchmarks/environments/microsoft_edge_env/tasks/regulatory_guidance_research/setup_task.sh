#!/bin/bash
# Setup for Regulatory Guidance Research task (FDA)
# Creates the research briefing, records baseline FDA visit counts and downloads,
# then launches Edge on fda.gov.

set -e

TASK_NAME="regulatory_guidance_research"
BRIEF_FILE="/home/ga/Desktop/research_brief.txt"
SUMMARY_FILE="/home/ga/Desktop/fda_research_summary.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
BASELINE_FILE="/tmp/task_baseline_${TASK_NAME}.json"

echo "=== Setting up ${TASK_NAME} ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# ── STEP 1: Kill Edge ─────────────────────────────────────────────────────────
echo "[1/5] Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# ── STEP 2: Remove stale summary file ────────────────────────────────────────
echo "[2/5] Removing stale summary file..."
rm -f "${SUMMARY_FILE}"

# ── STEP 3: Create the regulatory research briefing ──────────────────────────
echo "[3/5] Creating research briefing..."
cat > "${BRIEF_FILE}" << 'BRIEF_EOF'
REGULATORY AFFAIRS RESEARCH BRIEFING
Project: NovaMab-17 Phase III NDA Preparation
Prepared by: Regulatory Affairs Department, BioNovate Therapeutics
Date: Q1 2024

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BACKGROUND
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

NovaMab-17 is a monoclonal antibody (mAb) drug candidate currently completing
Phase III clinical trials for the treatment of moderate-to-severe rheumatoid
arthritis (RA). We are preparing to submit a New Drug Application (NDA) to
the U.S. Food and Drug Administration (FDA) under 21 CFR Part 314.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESEARCH TASKS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Please search FDA.gov (https://www.fda.gov) for current FDA guidance documents
relevant to the following clinical pharmacology topics for our NDA dossier:

1. PHARMACOKINETICS (PK): We need FDA guidance on characterizing the PK profile
   of NovaMab-17, including single- and multiple-dose studies, bioavailability,
   and population PK modeling requirements.

2. DRUG-DRUG INTERACTION (DDI) STUDIES: NovaMab-17 may be co-administered with
   methotrexate and other DMARDs. We need FDA guidance on DDI study design and
   reporting for the NDA.

3. SPECIAL POPULATIONS: We must characterize PK in patients with hepatic and
   renal impairment per FDA requirements. Please locate relevant guidance on
   pharmacokinetics in patients with organ impairment.

4. BIOEQUIVALENCE / REFERENCE PRODUCT (if applicable for any small-molecule
   components): Guidance on bioavailability and bioequivalence (BA/BE) studies.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DELIVERABLES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Download at least TWO FDA guidance documents (PDF) directly from fda.gov
   that are relevant to the topics above.

2. Organize bookmarks for all FDA guidance pages visited into an Edge Favorites
   folder named exactly: FDA Guidance

3. Write a regulatory research summary to /home/ga/Desktop/fda_research_summary.txt
   that includes:
   - Title of each guidance document found
   - The FDA URL or document identifier
   - One sentence describing the document scope and applicability to NovaMab-17

BRIEF_EOF
chown ga:ga "${BRIEF_FILE}"
echo "Research briefing created at ${BRIEF_FILE}"

# ── STEP 4: Record task start timestamp + baseline counts ─────────────────────
echo "[4/5] Recording baseline counts..."
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

python3 << 'PYEOF'
import sqlite3, shutil, json, os, sys

history_src = "/home/ga/.config/microsoft-edge/Default/History"
history_tmp = "/tmp/task_history_baseline_rgr.sqlite"
baseline_path = "/tmp/task_baseline_regulatory_guidance_research.json"

baseline = {"fda_count": 0, "download_count": 0, "fda_guidance_folder_exists": False}

if os.path.exists(history_src):
    try:
        shutil.copy2(history_src, history_tmp)
        conn = sqlite3.connect(history_tmp)
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%fda.gov%'")
        baseline["fda_count"] = cur.fetchone()[0] or 0
        cur.execute("SELECT COUNT(*) FROM downloads")
        baseline["download_count"] = cur.fetchone()[0] or 0
        conn.close()
        os.remove(history_tmp)
    except Exception as e:
        print(f"Warning: history query failed: {e}", file=sys.stderr)

bookmarks_path = "/home/ga/.config/microsoft-edge/Default/Bookmarks"
if os.path.exists(bookmarks_path):
    try:
        with open(bookmarks_path) as f:
            bm = json.load(f)
        def has_folder(node, name):
            if node.get("type") == "folder" and node.get("name","").strip().lower() == name.lower():
                return True
            return any(has_folder(c, name) for c in node.get("children", []))
        baseline["fda_guidance_folder_exists"] = any(
            has_folder(v, "FDA Guidance") for v in bm.get("roots", {}).values() if isinstance(v, dict)
        )
    except Exception as e:
        pass

with open(baseline_path, "w") as f:
    json.dump(baseline, f)

print(f"Baseline: fda={baseline['fda_count']}, downloads={baseline['download_count']}, "
      f"fda_guidance_folder={baseline['fda_guidance_folder_exists']}")
PYEOF

# ── STEP 5: Launch Edge on fda.gov and take start screenshot ─────────────────
echo "[5/5] Launching Microsoft Edge on FDA.gov..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    'https://www.fda.gov' \
    > /tmp/edge.log 2>&1 &"

TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft|fda"; then
        echo "Edge window appeared after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done
sleep 5

DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true
echo "Start screenshot saved to /tmp/${TASK_NAME}_start.png"

echo "=== Setup complete for ${TASK_NAME} ==="
echo "Research brief at: ${BRIEF_FILE}"
echo "Edge launched on: https://www.fda.gov"
