#!/usr/bin/env python3
"""
Verifier for create_discount_schema task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_discount_schema(traj, env_info, task_info):
    """
    Verifies the creation of a tiered discount schema in iDempiere.
    """
    # 1. Retrieve Result Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Define Targets
    TARGET_NAME = "Bulk Order Incentive 2024"
    TARGET_TYPE = "B" # Breaks
    TARGET_BREAKS = [
        {"qty": 10.0, "discount": 5.0},
        {"qty": 25.0, "discount": 8.0},
        {"qty": 50.0, "discount": 12.0},
        {"qty": 100.0, "discount": 15.0}
    ]

    score = 0
    feedback_parts = []
    
    # 3. Evaluation Criteria

    # Criterion 1: Schema Exists (15 pts)
    if result.get('schema_found'):
        score += 15
        feedback_parts.append("✅ Schema record found")
        
        details = result.get('schema_details', {})
        
        # Criterion 2: Correct Name (Implicit in search, but verifying exact match)
        if details.get('name') == TARGET_NAME:
             # Already awarded via search, but good for feedback
             pass
        
        # Criterion 3: Discount Type (10 pts)
        # 'B' is Breaks
        if details.get('type') == TARGET_TYPE:
            score += 10
            feedback_parts.append("✅ Correct Discount Type (Breaks)")
        else:
            feedback_parts.append(f"❌ Incorrect Discount Type: found '{details.get('type')}', expected 'B'")

        # Criterion 4: Active Status (5 pts)
        if details.get('active'):
            score += 5
            feedback_parts.append("✅ Schema is Active")
        else:
            feedback_parts.append("❌ Schema is NOT Active")
            
        # Criterion 5: Description (5 pts)
        if details.get('description') and len(details.get('description')) > 5:
            score += 5
            feedback_parts.append("✅ Description populated")
        else:
            feedback_parts.append("⚠️ Description missing or too short")

    else:
        feedback_parts.append(f"❌ Schema '{TARGET_NAME}' NOT found in database")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 6: Break Lines (50 pts total)
    breaks = result.get('breaks', [])
    
    # Check count (10 pts)
    if len(breaks) == 4:
        score += 10
        feedback_parts.append("✅ Correct number of break lines (4)")
    else:
        feedback_parts.append(f"❌ Incorrect break lines count: found {len(breaks)}, expected 4")

    # Check values (10 pts per correct line matched)
    matched_lines = 0
    
    for target in TARGET_BREAKS:
        t_qty = target['qty']
        t_disc = target['discount']
        found = False
        
        for b in breaks:
            try:
                b_qty = float(b.get('qty', 0))
                b_disc = float(b.get('discount', 0))
                
                # Tolerance check
                if abs(b_qty - t_qty) < 0.1 and abs(b_disc - t_disc) < 0.1:
                    found = True
                    break
            except ValueError:
                continue
        
        if found:
            matched_lines += 1
    
    score += (matched_lines * 10)
    if matched_lines == 4:
        feedback_parts.append("✅ All break tiers match expected values")
    else:
        feedback_parts.append(f"⚠️ Only {matched_lines}/4 break tiers matched expected values")

    # Criterion 7: Anti-Gaming / System State (15 pts)
    # Check if record count increased or if we found the specific record created after start
    # Note: DB created timestamp might be slightly off due to TZ, so we rely on finding the specific record 
    # plus the fact that we deleted it in setup.
    
    if result.get('current_count', 0) > result.get('initial_count', 0):
        score += 5
        feedback_parts.append("✅ Record count increased")
        
    if result.get('app_running'):
        score += 10
        feedback_parts.append("✅ Application running")
    else:
        feedback_parts.append("❌ Application was closed")

    # 4. Final Verdict
    # Threshold: 60 points required
    # Must have schema created (already checked) and at least 2 correct lines
    passed = score >= 60 and matched_lines >= 2
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }