#!/usr/bin/env python3
"""
Verifier for BMS Firmware Upgrade Task.
Scoring:
- Coverage: Created WO for all eligible assets.
- Precision: Did NOT create WO for ineligible assets.
- Quality: WO details (Priority, Description, Date) are correct.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bms_firmware_upgrade(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Variables
    score = 0
    feedback = []
    
    # 1. Coverage (30 pts)
    # Check if every eligible asset has at least one WO
    eligible_list = data.get("eligible_assets", [])
    total_eligible = len(eligible_list)
    covered_count = sum(1 for a in eligible_list if a["wo_count"] > 0)
    
    if total_eligible > 0:
        coverage_score = (covered_count / total_eligible) * 30
        score += coverage_score
        feedback.append(f"Coverage: {covered_count}/{total_eligible} assets ({int(coverage_score)}/30 pts)")
    else:
        feedback.append("Error: No eligible assets found in baseline.")

    # 2. Precision (20 pts)
    # Check that NO ineligible assets have WOs
    ineligible_list = data.get("ineligible_assets", [])
    total_ineligible = len(ineligible_list)
    wrong_count = sum(1 for a in ineligible_list if a["wo_count"] > 0)
    
    if total_ineligible > 0:
        if wrong_count == 0:
            score += 20
            feedback.append("Precision: Perfect (20/20 pts)")
        else:
            # Penalize heavily for wrong assets
            penalty = (wrong_count / total_ineligible) * 20
            precision_score = max(0, 20 - penalty)
            score += precision_score
            feedback.append(f"Precision: {wrong_count} ineligible assets wrongly targeted ({int(precision_score)}/20 pts)")

    # 3. Work Order Details (50 pts)
    # Check Description, Priority, Date for the VALID WOs
    details_score = 0
    valid_wos_checked = 0
    
    for asset in eligible_list:
        wos = asset.get("wos", [])
        if not wos: continue
        
        # Check the first linked WO
        wo = wos[0] 
        valid_wos_checked += 1
        
        # Description (contains CVE)
        desc = wo.get("description", "").lower()
        if "cve-2026-9912" in desc or "firmware" in desc:
            details_score += 5
        
        # Priority (Critical/High)
        prio = wo.get("priority", "").lower()
        if "critical" in prio or "high" in prio or "1" in prio:
            details_score += 5
            
        # Date (2026-06-15)
        date_str = wo.get("date", "")
        if "2026-06-15" in date_str:
            details_score += 5 # Exact match
        elif "2026" in date_str:
            details_score += 2 # Partial credit
            
    # Normalize details score to 50 max
    # We expect 3 eligible assets * 15 pts per asset = 45 raw pts. Scaling to 50.
    # Let's just sum it raw, maxing at 50 if they did extra good (unlikely).
    # Better: (details_score / (total_eligible * 15)) * 50
    
    if total_eligible > 0 and covered_count > 0:
        max_possible_details = covered_count * 15
        final_details_score = (details_score / max_possible_details) * 50
        score += final_details_score
        feedback.append(f"Details Quality: Checked {valid_wos_checked} WOs ({int(final_details_score)}/50 pts)")
    
    # Final Tally
    score = min(100, score)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }