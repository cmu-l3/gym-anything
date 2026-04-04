#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_split_pipeline_stage_and_redistribute(traj, env_info, task_info):
    """
    Verifies that:
    1. 'Proposition' stage is renamed to 'Proposition (Draft)'
    2. 'Proposition (Final)' stage is created and correctly sequenced
    3. High probability leads are moved to Final
    4. Low probability leads remain in Draft
    """
    
    # 1. Setup and retrieve data
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

    score = 0
    feedback_parts = []
    
    stages = result.get('stages', [])
    leads = result.get('leads', [])
    
    # 2. Verify Stages (40 pts total)
    prop_original = next((s for s in stages if s['name'].strip() == "Proposition"), None)
    prop_draft = next((s for s in stages if "Proposition (Draft)" in s['name']), None)
    prop_final = next((s for s in stages if "Proposition (Final)" in s['name']), None)
    
    # Check Rename
    if prop_original:
        feedback_parts.append("❌ Stage 'Proposition' still exists (should be renamed)")
    elif prop_draft:
        score += 20
        feedback_parts.append("✅ 'Proposition' renamed to 'Proposition (Draft)'")
    else:
        feedback_parts.append("❌ 'Proposition (Draft)' stage not found")

    # Check Creation
    if prop_final:
        score += 20
        feedback_parts.append("✅ 'Proposition (Final)' stage created")
    else:
        feedback_parts.append("❌ 'Proposition (Final)' stage not found")

    # 3. Verify Sequence (10 pts)
    if prop_draft and prop_final:
        if prop_draft['sequence'] < prop_final['sequence']:
            score += 10
            feedback_parts.append("✅ Stage sequence correct (Draft < Final)")
        else:
            feedback_parts.append(f"❌ Stage sequence incorrect (Draft: {prop_draft['sequence']} >= Final: {prop_final['sequence']})")
    
    # 4. Verify Lead Redistribution (50 pts total)
    high_prob_names = ["Global Logistics Contract", "Enterprise License Upgrade", "Q3 Managed Services"]
    low_prob_names = ["Office Expansion Inquiry", "Initial Consultation", "Hardware Refresh Estimate"]
    
    leads_correct = 0
    total_leads = len(high_prob_names) + len(low_prob_names)
    
    if not prop_draft or not prop_final:
        feedback_parts.append("❌ Cannot verify lead placement (missing stages)")
    else:
        for lead in leads:
            name = lead.get('name')
            # stage_id is [id, "Name"] in Odoo read results
            stage_id = lead.get('stage_id', [0, ''])[0] if lead.get('stage_id') else 0
            
            if name in high_prob_names:
                if stage_id == prop_final['id']:
                    leads_correct += 1
                else:
                    feedback_parts.append(f"❌ '{name}' is in wrong stage")
            elif name in low_prob_names:
                if stage_id == prop_draft['id']:
                    leads_correct += 1
                else:
                    feedback_parts.append(f"❌ '{name}' is in wrong stage")

        # Proportional score for leads (approx 8.3 pts per lead)
        lead_score = int((leads_correct / total_leads) * 50)
        score += lead_score
        feedback_parts.append(f"✅ {leads_correct}/{total_leads} leads correctly placed ({lead_score} pts)")

    # 5. Finalize
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }