#!/usr/bin/env python3
"""
Verifier for nist_cve_audit task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nist_cve_audit(traj, env_info, task_info):
    """
    Verify the NVD CVE audit task.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_data = metadata.get('cve_data', {})
    
    # 2. Copy result file
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
    
    # 3. Verify Browser Actions (History & Bookmarks) - 40 points
    
    # History (10 pts)
    if result.get('history_visits', 0) >= 3:
        score += 10
        feedback_parts.append("History check passed (+10)")
    elif result.get('history_visits', 0) > 0:
        score += 5
        feedback_parts.append("Partial history check (+5)")
    else:
        feedback_parts.append("No NVD visits found")

    # Bookmark Folder (15 pts)
    if result.get('folder_found'):
        score += 15
        feedback_parts.append("Bookmark folder found (+15)")
    else:
        feedback_parts.append("Bookmark folder 'Vulnerability Triage' missing")

    # Bookmarks Content (15 pts)
    bm_count = result.get('bookmark_count', 0)
    bm_urls = result.get('bookmark_urls', [])
    # Check if bookmarks look like NVD pages
    nvd_bms = sum(1 for url in bm_urls if 'nvd.nist.gov/vuln/detail/CVE-' in url)
    
    if nvd_bms >= 3:
        score += 15
        feedback_parts.append("Correct NVD bookmarks found (+15)")
    elif nvd_bms > 0:
        score += 5
        feedback_parts.append(f"Found {nvd_bms} NVD bookmarks (+5)")
    else:
        feedback_parts.append("No NVD detail bookmarks found")

    # 4. Verify Report Content - 60 points
    report_valid = result.get('report_valid_json', False)
    report_exists = result.get('report_exists', False)
    report_fresh = result.get('report_fresh', False)
    content = result.get('report_content', {})

    if not report_exists:
        feedback_parts.append("Report file missing")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    if not report_fresh:
        feedback_parts.append("Report file not created during task") # Anti-gaming
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    if not report_valid:
        score += 5 # Small credit for file existence
        feedback_parts.append("Report exists but invalid JSON (+5)")
    else:
        score += 10 # Credit for valid JSON
        
        # Check each CVE (50 points distributed)
        # 16.6 points per CVE -> breakdown: Score (5), Vector (5), CWE (6)
        
        for cve_id, expected in expected_data.items():
            entry = content.get(cve_id)
            if not entry:
                feedback_parts.append(f"Missing {cve_id}")
                continue
                
            # Check Score (within tolerance)
            try:
                actual_score = float(entry.get('cvss_score', 0))
                if abs(actual_score - expected['score']) <= 0.1:
                    score += 5
                else:
                    feedback_parts.append(f"{cve_id} score mismatch ({actual_score} vs {expected['score']})")
            except:
                feedback_parts.append(f"{cve_id} score invalid")

            # Check Vector (exact match preferred)
            actual_vector = str(entry.get('vector_string', '')).strip()
            if actual_vector == expected['vector']:
                score += 5
            elif actual_vector.startswith("CVSS:3"):
                score += 2 # Partial credit for format
                feedback_parts.append(f"{cve_id} vector mismatch")
            else:
                feedback_parts.append(f"{cve_id} vector invalid")

            # Check CWE (contains ID)
            actual_cwe = str(entry.get('cwe_id', '')).upper()
            expected_cwe_num = expected['cwe'].split('-')[-1] # e.g. "502" from "CWE-502"
            
            if expected_cwe_num in actual_cwe:
                score += 6  # ~16 points total per CVE
            else:
                feedback_parts.append(f"{cve_id} CWE mismatch (got {actual_cwe})")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }