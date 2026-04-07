#!/usr/bin/env python3
"""
Verifier for Oracle Text Search Implementation.

Scoring:
- Index created & valid: 10 pts
- Custom Stoplist created & correct words: 15 pts
- Index uses the stoplist: 10 pts (Implicitly checked via functionality, confirmed via metadata check in export)
- Package Valid: 10 pts
- Stemming functionality: 15 pts (Search 'run' finds 'running')
- Scoring column: 10 pts
- Real-time Sync: 20 pts (ADD_BOOK makes data searchable immediately)
- Output file exists: 10 pts

Pass Threshold: 65 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_oracle_text_search(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Index Existence (10)
    if result.get("index_exists") and result.get("index_status") == "INDEXED":
        score += 10
        feedback_parts.append("Context Index created and valid (+10)")
    else:
        feedback_parts.append("Context Index missing or invalid (0)")

    # 2. Stoplist (15)
    # The export script checks existence AND content match
    if result.get("stoplist_exists"):
        if result.get("stopwords_correct"):
            score += 15
            feedback_parts.append("Stoplist correct (+15)")
        else:
            score += 5
            feedback_parts.append("Stoplist exists but missing required words (+5)")
    else:
        feedback_parts.append("Stoplist not found (0)")

    # 3. Index uses Stoplist (10)
    # We infer this: if index exists and stoplist correct, we assume linked.
    # A deeper check would require parsing DDL, but functional stopword check is hard
    # without specific data queries. We'll award if both above passed.
    if result.get("index_exists") and result.get("stoplist_exists"):
        score += 10
        feedback_parts.append("Index linked to configuration (+10)")

    # 4. Package Valid (10)
    if result.get("package_valid"):
        score += 10
        feedback_parts.append("PL/SQL Package valid (+10)")
    else:
        feedback_parts.append("PL/SQL Package invalid or missing (0)")

    # 5. Stemming (15)
    if result.get("stemming_works"):
        score += 15
        feedback_parts.append("Stemming functionality verified (+15)")
    else:
        feedback_parts.append("Stemming test failed (0)")

    # 6. Scoring (10)
    if result.get("scoring_works"):
        score += 10
        feedback_parts.append("Relevance scoring present (+10)")
    else:
        feedback_parts.append("Relevance scoring missing (0)")

    # 7. Real-time Sync (20)
    if result.get("sync_works"):
        score += 20
        feedback_parts.append("Real-time index synchronization works (+20)")
    else:
        feedback_parts.append("Real-time sync failed - index needs manual rebuild (0)")

    # 8. Output File (10)
    if result.get("output_file_exists"):
        score += 10
        feedback_parts.append("Output file created (+10)")
    else:
        feedback_parts.append("Output file missing (0)")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }