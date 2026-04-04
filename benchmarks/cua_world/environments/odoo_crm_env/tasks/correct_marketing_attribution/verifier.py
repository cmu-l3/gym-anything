#!/usr/bin/env python3
import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_marketing_attribution(traj, env_info, task_info):
    """
    Verifies that the agent correctly updated marketing attribution on 3 opportunities.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('target_opportunities', [])
    
    # Retrieve result file
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

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    # Extract reference IDs
    ref_ids = result.get('utm_ids', {})
    ref_camp_id = ref_ids.get('campaign_id')
    ref_med_id = ref_ids.get('medium_id')
    ref_src_id = ref_ids.get('source_id')

    if not all([ref_camp_id, ref_med_id, ref_src_id]):
        return {"passed": False, "score": 0, "feedback": "Setup failed: UTM records missing in database"}

    score = 0
    feedback_lines = []
    
    # Helper to check modification time
    task_start_ts = result.get('task_start', 0)
    
    opportunities_data = result.get('opportunities', {})
    
    # Check each opportunity
    perfect_opportunities = 0
    
    for name in targets:
        opp_data = opportunities_data.get(name)
        if not opp_data or not opp_data.get('found'):
            feedback_lines.append(f"❌ '{name}': Not found or deleted")
            continue

        # Check values
        c_ok = opp_data.get('campaign_id') == ref_camp_id
        m_ok = opp_data.get('medium_id') == ref_med_id
        s_ok = opp_data.get('source_id') == ref_src_id
        
        # Check timestamp (Odoo stores UTC string usually, but we can do a loose check if needed)
        # For simplicity in this robust verifier, we rely on the DB state. 
        # Advanced: parse 'write_date' string vs timestamp if stricter anti-gaming needed.
        # Here we assume DB state is sufficient proof of work for this specific task structure.

        item_score = 0
        if c_ok: item_score += 10
        if m_ok: item_score += 10
        if s_ok: item_score += 10
        
        score += item_score
        
        status_str = []
        if c_ok: status_str.append("Campaign OK")
        else: status_str.append(f"Campaign: {opp_data.get('campaign_name') or 'None'}")
        
        if m_ok: status_str.append("Medium OK")
        else: status_str.append(f"Medium: {opp_data.get('medium_id') or 'None'}")
        
        if s_ok: status_str.append("Source OK")
        else: status_str.append(f"Source: {opp_data.get('source_id') or 'None'}")

        if item_score == 30:
            perfect_opportunities += 1
            feedback_lines.append(f"✅ '{name}': All Correct")
        else:
            feedback_lines.append(f"⚠️ '{name}': {', '.join(status_str)}")

    # Consistency Bonus
    if perfect_opportunities == 3:
        score += 10
        feedback_lines.append("✅ Bonus: All records perfectly consistent (10 pts)")

    # Final check
    passed = (score >= 90) # Requires essentially perfection

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }