#!/bin/bash
# pre_task hook for editorial_review_pipeline task.
# CLEAN → SEED → LAUNCH ordering (Lesson 169).
# No set -e (Lesson 174).

echo "=== Setting up editorial_review_pipeline task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# =====================================================================
# CLEAN: Remove state from previous runs
# =====================================================================
echo "Cleaning previous task state..."

# Remove ready-for-review and needs-revision tags from all known documents
for DOC_PATH in \
    "/default-domain/workspaces/Projects/Feature-Article-Climate-Change" \
    "/default-domain/workspaces/Projects/Research-Report-AI-Ethics" \
    "/default-domain/workspaces/Projects/Opinion-Column-Economic-Policy" \
    "/default-domain/workspaces/Projects/Breaking-News-Tech-Sector"; do
    curl -s -u "$NUXEO_AUTH" -X DELETE \
        "$NUXEO_URL/api/v1/path${DOC_PATH}/@tagging/ready-for-review" > /dev/null 2>&1 || true
    curl -s -u "$NUXEO_AUTH" -X DELETE \
        "$NUXEO_URL/api/v1/path${DOC_PATH}/@tagging/needs-revision" > /dev/null 2>&1 || true
done

# Delete Q4 2025 Publications collection
COLL_SEARCH=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Collection+WHERE+dc:title='Q4+2025+Publications'+AND+ecm:isTrashed=0+AND+ecm:isVersion=0" 2>/dev/null)
COLL_UID=$(echo "$COLL_SEARCH" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    entries = d.get('entries', [])
    if entries: print(entries[0].get('uid', ''))
except: pass
" 2>/dev/null || echo "")
if [ -n "$COLL_UID" ]; then
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${COLL_UID}?permanent=true" > /dev/null 2>&1 || true
    echo "Deleted previous Q4 2025 Publications collection."
fi

# Delete editorial assessment notes (search for assessment notes created by previous runs)
ASSESS_SEARCH=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Note+WHERE+dc:title+LIKE+'%25Assessment%25'+AND+ecm:path+STARTSWITH+'/default-domain/workspaces/Projects'+AND+ecm:isTrashed=0+AND+ecm:isVersion=0&pageSize=20" 2>/dev/null)
ASSESS_UIDS=$(echo "$ASSESS_SEARCH" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for e in d.get('entries', []):
        uid = e.get('uid', '')
        title = e.get('title', '').lower()
        if uid and 'assessment' in title:
            print(uid)
except: pass
" 2>/dev/null || true)
for AUID in $ASSESS_UIDS; do
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${AUID}?permanent=true" > /dev/null 2>&1 || true
done

# Delete the editorial standards note (will recreate)
if doc_exists "/default-domain/workspaces/Projects/Editorial-Standards-and-Publication-Guidelines"; then
    ESG_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Editorial-Standards-and-Publication-Guidelines" | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
    [ -n "$ESG_UID" ] && curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${ESG_UID}?permanent=true" > /dev/null 2>&1 || true
fi

# Delete and recreate article documents (reset their metadata)
for DOC_PATH in \
    "/default-domain/workspaces/Projects/Feature-Article-Climate-Change" \
    "/default-domain/workspaces/Projects/Research-Report-AI-Ethics" \
    "/default-domain/workspaces/Projects/Opinion-Column-Economic-Policy" \
    "/default-domain/workspaces/Projects/Breaking-News-Tech-Sector"; do
    if doc_exists "$DOC_PATH"; then
        D_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path${DOC_PATH}" | \
            python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
        [ -n "$D_UID" ] && curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${D_UID}?permanent=true" > /dev/null 2>&1 || true
    fi
done

sleep 2

# =====================================================================
# SEED: Create documents with varying states of metadata completeness
# =====================================================================
echo "Seeding editorial documents..."

# Doc 1: Feature article — has description but MISSING source, rights, language
nuxeo_api POST "/path/default-domain/workspaces/Projects/" '{
  "entity-type":"document","type":"Note","name":"Feature-Article-Climate-Change",
  "properties":{
    "dc:title":"Feature Article: The Hidden Costs of Climate Inaction",
    "dc:description":"An in-depth feature examining the economic and social costs of delayed climate action, drawing on IPCC AR6 data and interviews with leading economists from the Brookings Institution.",
    "note:note":"<h2>The Hidden Costs of Climate Inaction</h2><p>This feature article examines the latest research on the economic toll of deferred climate policy. Drawing on the IPCC Sixth Assessment Report and interviews with economists at the Brookings Institution and Resources for the Future, we explore how inaction today multiplies costs tomorrow. Key findings: every year of delay adds approximately $1.6 trillion to the global adaptation burden. The social cost of carbon, now estimated at $185 per metric ton by the EPA, underpins a growing body of policy analysis demonstrating that the cost of action is far lower than the cost of inaction.</p>",
    "dc:source":"",
    "dc:rights":"",
    "dc:language":""
  }
}' > /dev/null 2>&1

# Doc 2: Research report — has description and source but MISSING rights and language
nuxeo_api POST "/path/default-domain/workspaces/Projects/" '{
  "entity-type":"document","type":"Note","name":"Research-Report-AI-Ethics",
  "properties":{
    "dc:title":"Research Report: Algorithmic Accountability in Hiring Systems",
    "dc:description":"A peer-reviewed research report examining bias amplification in AI-assisted recruitment tools, with case studies from financial services and healthcare sectors.",
    "note:note":"<h2>Algorithmic Accountability in Hiring Systems</h2><p>This report synthesizes findings from three years of field research into AI-assisted recruitment tools deployed at 47 enterprise organizations. We identify systematic bias amplification patterns in resume screening algorithms, with disparate impact ratios ranging from 1.3 to 2.8 across protected categories. Methodological contributions include a novel audit framework for detecting indirect discrimination in opaque scoring models. Policy recommendations are addressed to HR technology vendors, enterprise buyers, and regulatory agencies.</p>",
    "dc:source":"Dr. Sarah Chen, MIT Media Lab — Computational Policy Research Group",
    "dc:rights":"",
    "dc:language":""
  }
}' > /dev/null 2>&1

# Doc 3: Opinion column — has ALL required metadata (should be tagged 'ready-for-review')
nuxeo_api POST "/path/default-domain/workspaces/Projects/" '{
  "entity-type":"document","type":"Note","name":"Opinion-Column-Economic-Policy",
  "properties":{
    "dc:title":"Opinion: Rethinking Monetary Policy in a Multipolar World",
    "dc:description":"An opinion column arguing that central bank independence frameworks must adapt to geopolitical fragmentation and the rise of BRICS+ currency alternatives.",
    "note:note":"<h2>Rethinking Monetary Policy in a Multipolar World</h2><p>The Bretton Woods consensus, though never explicitly declared dead, has been quietly eroding for a decade. The rise of BRICS+ payment systems, the weaponization of SWIFT, and the acceleration of central bank digital currency pilots signal a structural shift in the international monetary order. This column argues that central banks in advanced economies have been slow to update their operating frameworks for a world of geopolitical fragmentation. The Taylor Rule, optimized for a unipolar era of deep financial integration, provides poor guidance when supply chains are deliberately decoupled and capital flows are subject to political risk premiums.</p>",
    "dc:source":"Prof. James Okonkwo, Harvard Kennedy School",
    "dc:rights":"Copyright 2025 Meridian Publishing Group. All rights reserved.",
    "dc:language":"en"
  }
}' > /dev/null 2>&1

# Doc 4: Breaking news — MISSING source, rights, and language (all three gaps)
nuxeo_api POST "/path/default-domain/workspaces/Projects/" '{
  "entity-type":"document","type":"Note","name":"Breaking-News-Tech-Sector",
  "properties":{
    "dc:title":"Breaking: Major Tech Merger Raises Antitrust Concerns in EU",
    "dc:description":"Breaking news coverage of the proposed $47B acquisition between two major cloud infrastructure providers, focusing on European Commission preliminary findings.",
    "note:note":"<h2>Breaking: Major Tech Merger Raises Antitrust Concerns in EU</h2><p>The European Commission announced preliminary findings Thursday that the proposed acquisition raises significant concerns under Article 2 of the EU Merger Regulation. Commission Vice President Margrethe Vestager stated that the combined entity would control approximately 34% of the European Infrastructure-as-a-Service market, potentially allowing the merged company to leverage its position in adjacent markets including enterprise software and edge computing. The companies have 10 business days to propose remedies. Market reaction was swift, with shares in both companies declining.</p>",
    "dc:source":"",
    "dc:rights":"",
    "dc:language":""
  }
}' > /dev/null 2>&1

echo "Editorial documents seeded."

# Create the Editorial Standards and Publication Guidelines reference document
echo "Creating Editorial Standards reference document..."
STANDARDS_PAYLOAD=$(cat <<'STANDARDS_JSON'
{
  "entity-type": "document",
  "type": "Note",
  "name": "Editorial-Standards-and-Publication-Guidelines",
  "properties": {
    "dc:title": "Editorial Standards and Publication Guidelines",
    "dc:description": "Q4 2025 publication cycle metadata requirements and editorial workflow guidelines",
    "note:note": "<h2>Editorial Standards and Publication Guidelines</h2><h3>Q4 2025 Publication Cycle</h3><p><strong>Effective:</strong> October 1, 2025 | <strong>Review Editor:</strong> Digital Content Manager</p><hr/><h3>Purpose</h3><p>This document defines the metadata completeness requirements for all content entering the Q4 2025 publication cycle. Every document must be reviewed against these standards before entering the publication queue.</p><h3>Required Metadata Fields</h3><p>All documents intended for publication must have the following Dublin Core metadata fields populated:</p><ol><li><strong>dc:source</strong> — The original author, contributing writer, or institutional source of the content (e.g., \"Jane Smith, Reuters\" or \"Dr. Alan Park, Stanford University\"). Cannot be empty.</li><li><strong>dc:rights</strong> — The copyright or licensing statement for the content (e.g., \"Copyright 2025 Meridian Publishing. All rights reserved.\" or \"Creative Commons Attribution 4.0 International\"). Cannot be empty.</li><li><strong>dc:language</strong> — ISO 639-1 language code for the primary language of the document (e.g., \"en\" for English, \"fr\" for French, \"de\" for German). Cannot be empty.</li></ol><h3>Editorial Workflow Tagging</h3><p>After reviewing each document's metadata completeness, apply one of the following workflow tags:</p><ul><li><strong>ready-for-review</strong> — Apply to documents that have ALL THREE required metadata fields (dc:source, dc:rights, dc:language) populated with valid, non-empty values. These documents are cleared to enter the publication queue.</li><li><strong>needs-revision</strong> — Apply to documents that are MISSING one or more of the required metadata fields. These documents require author follow-up before they can proceed.</li></ul><h3>Editorial Assessment Notes</h3><p>For each document reviewed, create a Note document in this workspace titled \"[Document Title] — Editorial Assessment\" containing your evaluation: which fields are present, which are missing, whether the document is ready for publication, and any recommendations for the author.</p><h3>Q4 2025 Publications Collection</h3><p>Upon completion of the review cycle, create a collection called <strong>Q4 2025 Publications</strong> and add all documents tagged <strong>ready-for-review</strong> to this collection. This collection will be used by the layout team for the Q4 editorial calendar.</p>"
  }
}
STANDARDS_JSON
)
nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$STANDARDS_PAYLOAD" > /dev/null 2>&1
echo "Editorial Standards document created."

sleep 2

# =====================================================================
# LAUNCH: Open Firefox, log in, navigate to Nuxeo home
# =====================================================================
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

sleep 3
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

sleep 2
navigate_to "$NUXEO_UI/#!/home"
sleep 3

echo "Task start state: Firefox on Nuxeo home page."
echo "Agent must read Editorial Standards, review 4 articles, update metadata,"
echo "apply tags, create assessment notes, and build Q4 2025 Publications collection."
echo "=== editorial_review_pipeline setup complete ==="
