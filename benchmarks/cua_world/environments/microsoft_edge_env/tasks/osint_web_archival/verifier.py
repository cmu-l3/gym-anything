#!/usr/bin/env python3
"""
Verifier for OSINT Web Archival task.

Scoring (100 points total):
- 3 Target Files (15 pts each = 45 pts):
  - Must exist, be valid MHTML (headers), >10KB, and created during task.
- 3 Domain Visits (5 pts each = 15 pts):
  - Browser history must show visits to target domains.
- Directory Creation (5 pts):
  - Target folder exists.
- Catalog File (35 pts total):
  - Exists & created during task: 10 pts
  - Contains all 3 URLs/Domains: 15 pts
  - Contains all 3 Filenames: 10 pts

Pass Threshold: 65 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/osint_web_archival_result.json"

def verify_osint_web_archival(traj, env_info, task_info):
    """Verify the OSINT Web Archival task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    
    files = result.get("files", {})
    catalog = result.get("catalog", {})
    dir_created = result.get("directory_created", False)

    # 1. Directory Check (5 pts)
    if dir_created:
        score += 5
        feedback_parts.append("Evidence directory created (5/5)")
    else:
        feedback_parts.append("Evidence directory NOT created (0/5)")

    # 2. File Checks (45 pts + 15 pts history)
    # Targets: cia_world_factbook.mhtml, fbi_most_wanted.mhtml, ofac_sanctions.mhtml
    
    for fname, data in files.items():
        # File Validity (15 pts per file)
        # Requirements: Exists, Valid Header, >10KB size, Created during task
        file_ok = (data.get("exists") and 
                   data.get("valid_mhtml_header") and 
                   data.get("size_bytes", 0) > 10240 and 
                   data.get("created_during_task"))
        
        if file_ok:
            score += 15
            feedback_parts.append(f"{fname}: Valid MHTML archive (15/15)")
        elif data.get("exists"):
            # Partial credit for existing but invalid/small file
            score += 5
            feedback_parts.append(f"{fname}: Exists but invalid/too small/stale (5/15)")
        else:
            feedback_parts.append(f"{fname}: Missing (0/15)")

        # History Check (5 pts per domain)
        if data.get("domain_visited"):
            score += 5
            feedback_parts.append(f"{fname} domain: Visited (5/5)")
        else:
            feedback_parts.append(f"{fname} domain: NOT visited (0/5)")

    # 3. Catalog Checks (35 pts)
    # Exists & New (10 pts)
    if catalog.get("exists") and catalog.get("created_during_task") and catalog.get("size_bytes", 0) > 200:
        score += 10
        feedback_parts.append("Catalog: Exists and valid size (10/10)")
        
        # Valid Content (25 pts split)
        # We did a rough check in export_result.sh, but let's trust that flag for now 
        # as it checks for all URLs and filenames.
        if catalog.get("valid_content"):
            score += 25
            feedback_parts.append("Catalog: Content verified (URLs and filenames present) (25/25)")
        else:
            # Partial check based on preview if available (omitted for simplicity, relying on export logic)
            feedback_parts.append("Catalog: Missing some required URLs or filenames (0/25)")
    elif catalog.get("exists"):
        score += 5
        feedback_parts.append("Catalog: Exists but stale or empty (5/35)")
    else:
        feedback_parts.append("Catalog: Missing (0/35)")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }