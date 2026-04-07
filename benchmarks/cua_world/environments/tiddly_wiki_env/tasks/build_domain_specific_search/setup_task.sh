#!/bin/bash
echo "=== Setting up build_domain_specific_search task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_start_time

# Seed the wiki with domain-specific clinical data
echo "Creating seed clinical guidelines and noisy data..."

# Active Guideline 1
cat > "$TIDDLER_DIR/Guideline_ Sepsis Protocol.tid" << 'EOF'
title: Guideline: Sepsis Protocol
tags: ClinicalGuideline Active

Immediate administration of broad-spectrum antibiotics and 30ml/kg crystalloid fluid for sepsis or septic shock within 1 hour.
EOF

# Active Guideline 2
cat > "$TIDDLER_DIR/Guideline_ Diabetic Ketoacidosis (DKA).tid" << 'EOF'
title: Guideline: Diabetic Ketoacidosis (DKA)
tags: ClinicalGuideline Active

Insulin drip protocols and continuous fluid resuscitation pathways for DKA management in adult patients.
EOF

# Active Guideline 3
cat > "$TIDDLER_DIR/Guideline_ Acute Myocardial Infarction.tid" << 'EOF'
title: Guideline: Acute Myocardial Infarction
tags: ClinicalGuideline Active

Standard STEMI protocol. Administer aspirin 324mg and activate cath lab immediately upon positive ECG.
EOF

# Archived Guideline (Contains the keyword "sepsis" to test filter precision)
cat > "$TIDDLER_DIR/Guideline_ Old COVID-19 Pathway.tid" << 'EOF'
title: Guideline: Old COVID-19 Pathway
tags: ClinicalGuideline Archived

Archived 2021 guidelines. Note that severe COVID-19 can mimic viral sepsis.
EOF

# Noisy Data (Contains the keyword "sepsis" but lacks proper tags)
cat > "$TIDDLER_DIR/Meeting Minutes_ Q3 Nursing Staff.tid" << 'EOF'
title: Meeting Minutes: Q3 Nursing Staff
tags: Meetings Administration

Discussed the upcoming holiday schedule and briefly reviewed the roll-out of the new sepsis protocol. 
EOF

# Fix permissions
chown -R ga:ga "$TIDDLER_DIR"

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count
echo "Initial tiddler count: $INITIAL_COUNT"

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

# Ensure Firefox is focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="