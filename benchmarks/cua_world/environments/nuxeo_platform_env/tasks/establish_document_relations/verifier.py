#!/usr/bin/env python3
"""
Verifier for establish_document_relations task.

Scoring Criteria:
1. API Relation Checks (75 pts total):
   - Annual Report -> IsBasedOn -> Proposal (25 pts)
   - Annual Report -> References -> Q3 Status (25 pts)
   - Contract Template -> ConformsTo -> Annual Report (25 pts)
2. Report File (20 pts total):
   - Exists and lists 3 relations (15 pts)
   - Created during task window (5 pts)
3. Anti-gaming (5 pts):
   - Initial state was clean (no pre-existing relations)

Total: 100 pts
Pass Threshold: 50 pts (must get at least 2 relations correct)
"""

import json
import base64
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_establish_document_relations(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # 1. API Verification (75 pts)
    # ----------------------------------------------------------------
    api_res = result.get("api_results", {})
    
    # Relation 1: IsBasedOn
    if api_res.get("relation_1_found"):
        score += 25
        feedback_parts.append("Relation 'IsBasedOn' confirmed (+25)")
    else:
        feedback_parts.append("Relation 'IsBasedOn' NOT found")

    # Relation 2: References
    if api_res.get("relation_2_found"):
        score += 25
        feedback_parts.append("Relation 'References' confirmed (+25)")
    else:
        feedback_parts.append("Relation 'References' NOT found")

    # Relation 3: ConformsTo
    if api_res.get("relation_3_found"):
        score += 25
        feedback_parts.append("Relation 'ConformsTo' confirmed (+25)")
    else:
        feedback_parts.append("Relation 'ConformsTo' NOT found")

    # ----------------------------------------------------------------
    # 2. Report File Verification (20 pts)
    # ----------------------------------------------------------------
    if result.get("report_exists"):
        # Check content
        b64_content = result.get("report_content_b64", "")
        try:
            content = base64.b64decode(b64_content).decode('utf-8')
            lines = [l.strip() for l in content.splitlines() if l.strip()]
            
            # Simple check: expect roughly 3 lines, mention document names
            line_count = len(lines)
            has_keywords = "Annual" in content and "Proposal" in content and "Contract" in content
            
            if line_count >= 3 and has_keywords:
                score += 15
                feedback_parts.append("Report file valid (+15)")
            else:
                score += 5
                feedback_parts.append(f"Report file exists but content incomplete (lines: {line_count}) (+5)")
        except:
            score += 5
            feedback_parts.append("Report file exists but unreadable (+5)")

        # Timestamp check
        if result.get("report_valid_timestamp"):
            score += 5
            feedback_parts.append("Report created during task (+5)")
        else:
            feedback_parts.append("Report file is old/stale")
    else:
        feedback_parts.append("Report file missing")

    # ----------------------------------------------------------------
    # 3. Anti-Gaming (5 pts)
    # ----------------------------------------------------------------
    if result.get("initial_state_clean", True):
        score += 5
        feedback_parts.append("Initial state clean (+5)")
    else:
        feedback_parts.append("Warning: Initial state not clean (possible pre-seeding)")

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    passed = score >= 50
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }