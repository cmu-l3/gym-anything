#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tag_competitor_mentions(traj, env_info, task_info):
    """
    Verify the 'tag_competitor_mentions' task.
    
    Scoring Criteria:
    1. Tag 'Competitor: OmniTech' exists (20 pts)
    2. Tag created AFTER task start (Anti-gaming) (Pass/Fail check)
    3. Precision: Only leads with 'OmniTech' in notes are tagged (40 pts)
    4. Recall: All leads with 'OmniTech' in notes are tagged (40 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback = []
    
    # 1. Check Tag Existence (20 pts)
    if result.get("tag_exists"):
        score += 20
        feedback.append("Tag 'Competitor: OmniTech' created.")
    else:
        feedback.append("Tag 'Competitor: OmniTech' NOT found.")
        return {"passed": False, "score": 0, "feedback": "Tag was not created."}

    # 2. Check Tag assignments
    leads = result.get("leads", {})
    
    # Expected Ground Truth
    should_be_tagged = [
        "Server Upgrade - CyberDyne Systems", 
        "Consulting Services - Wayne Enterprises"
    ]
    should_NOT_be_tagged = [
        "Office Expansion - KwikE Mart", 
        "Fleet Management - Planet Express", 
        "Software License - Stark Industries"
    ]

    # Calculate Recall (Did we find the right ones?)
    tagged_correctly_count = 0
    for name in should_be_tagged:
        if leads.get(name, {}).get("has_target_tag"):
            tagged_correctly_count += 1
        else:
            feedback.append(f"Missed: '{name}' (contained OmniTech but not tagged)")

    # 40 points for recall (20 points per correct lead)
    recall_score = (tagged_correctly_count / len(should_be_tagged)) * 40
    score += recall_score
    if recall_score == 40:
        feedback.append("Recall perfect: All matching opportunities tagged.")

    # Calculate Precision (Did we avoid tagging the wrong ones?)
    false_positives = 0
    for name in should_NOT_be_tagged:
        if leads.get(name, {}).get("has_target_tag"):
            false_positives += 1
            feedback.append(f"False Positive: '{name}' (tagged but does not mention OmniTech)")
    
    # 40 points for precision. Lose 20 points for each false positive.
    precision_score = max(0, 40 - (false_positives * 20))
    score += precision_score
    if precision_score == 40:
        feedback.append("Precision perfect: No incorrect opportunities tagged.")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }