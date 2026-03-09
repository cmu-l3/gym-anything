#!/usr/bin/env python3
import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_hot_lead_server_action(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    task_start_ts = data.get("task_start_timestamp", 0)
    action = data.get("server_action", {})
    action_lines = data.get("action_lines", [])
    opportunity = data.get("opportunity", {})
    
    score = 0
    feedback = []

    # 3. Verify Server Action Configuration
    if action.get("exists"):
        score += 20
        feedback.append("Server Action 'Mark as Hot Lead' created.")

        # Check Model (should contain 'Lead' or 'Opportunity')
        model_name = action.get("model_name", "")
        if "Lead" in model_name or "Opportunity" in model_name or "crm.lead" in model_name:
            score += 10
            feedback.append("Action linked to correct model.")
        else:
            feedback.append(f"Action linked to wrong model: {model_name}")

        # Check Contextual Action (Binding)
        if action.get("is_bound"):
            score += 20
            feedback.append("Contextual Action created (added to 'Actions' menu).")
        else:
            feedback.append("Contextual Action NOT created (not bound to model).")

        # Check Updates (Lines)
        # Look for priority and probability in the update lines
        # Value for Priority '3' (High) is often stored as '3' string in Python expr or value
        # Value for Probability 90 is '90'
        
        priority_set = False
        probability_set = False
        
        for line in action_lines:
            field = line.get('field', '')
            val = str(line.get('value', ''))
            
            if field == 'priority' and '3' in val:
                priority_set = True
            if field == 'probability' and '90' in val:
                probability_set = True
                
        if priority_set:
            score += 10
            feedback.append("Action config: Priority set to High.")
        else:
            feedback.append("Action config: Priority NOT set correctly.")
            
        if probability_set:
            score += 10
            feedback.append("Action config: Probability set to 90%.")
        else:
            feedback.append("Action config: Probability NOT set correctly.")

    else:
        feedback.append("Server Action 'Mark as Hot Lead' NOT found.")

    # 4. Verify Execution (Opportunity State)
    if opportunity:
        # Check Priority (Odoo stores as string '0', '1', '2', '3')
        # 3 is High/Very High
        actual_priority = str(opportunity.get('priority', ''))
        if actual_priority == '3':
            score += 10
            feedback.append("Target opportunity Priority is High (3).")
        else:
            feedback.append(f"Target opportunity Priority is {actual_priority} (expected 3).")

        # Check Probability
        actual_prob = opportunity.get('probability', 0)
        if actual_prob == 90:
            score += 10
            feedback.append("Target opportunity Probability is 90%.")
        else:
            feedback.append(f"Target opportunity Probability is {actual_prob}% (expected 90%).")

        # Check Timestamp (Anti-Gaming)
        # Odoo write_date is UTC string "YYYY-MM-DD HH:MM:SS"
        write_date_str = opportunity.get('write_date', '')
        if write_date_str:
            try:
                # Basic parsing, might need adjustment if Odoo adds fractional seconds
                write_dt = datetime.fromisoformat(write_date_str)
                write_ts = write_dt.timestamp()
                
                # Allow a small buffer (e.g. server time skew), but essentially must be after task start
                if write_ts >= task_start_ts:
                    score += 10
                    feedback.append("Update occurred during task.")
                else:
                    feedback.append("Update occurred BEFORE task start (stale data).")
            except Exception as e:
                # If parsing fails, leniently skip timestamp check but warn
                logger.warning(f"Could not parse write_date: {e}")
                feedback.append("Could not verify execution time.")
        else:
            feedback.append("No write_date found on opportunity.")
    else:
        feedback.append("Target opportunity not found.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }