#!/usr/bin/env python3
import json
import logging
import os
import tempfile
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_sales_opportunity(traj, env_info, task_info):
    """
    Verifies the creation of a Sales Opportunity in iDempiere.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    record = result.get('record', {})
    found = result.get('found', False)
    task_start_ts = result.get('task_start_ts', 0)
    
    # 3. Score Calculation
    score = 0
    feedback_log = []
    
    # CRITERION 1: Record Existence (20 pts)
    if found:
        score += 20
        feedback_log.append("✅ Opportunity record 'Oak Street Office Park' found.")
    else:
        feedback_log.append("❌ Opportunity record not found in database.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback_log)}

    # CRITERION 2: Anti-Gaming / Freshness (10 pts)
    # Check if created timestamp is after task start
    created_ts = record.get('created_ts', 0)
    if created_ts > task_start_ts:
        score += 10
        feedback_log.append("✅ Record was created during this session.")
    else:
        feedback_log.append("⚠️ Record appears to be stale (created before task start).")

    # CRITERION 3: Business Partner (20 pts)
    bp_name = record.get('bp_name', '')
    if "C&W Construction" in bp_name:
        score += 20
        feedback_log.append(f"✅ Business Partner correct: {bp_name}")
    else:
        feedback_log.append(f"❌ Business Partner mismatch. Expected 'C&W Construction', got '{bp_name}'")

    # CRITERION 4: Financials (20 pts)
    # Amount 120,000 and Prob 40
    try:
        amt = float(record.get('amount', 0))
        prob = float(record.get('probability', 0))
        
        if abs(amt - 120000) < 1.0:
            score += 10
            feedback_log.append("✅ Expected Amount correct (120,000).")
        else:
            feedback_log.append(f"❌ Amount incorrect. Got {amt}.")
            
        if abs(prob - 40) < 1.0:
            score += 10
            feedback_log.append("✅ Probability correct (40%).")
        else:
            feedback_log.append(f"❌ Probability incorrect. Got {prob}%.")
    except ValueError:
        feedback_log.append("❌ Error parsing numeric values.")

    # CRITERION 5: Date Accuracy (15 pts)
    # Expected close date: 3 months from today (+/- 7 days tolerance)
    date_str = record.get('close_date', '')
    if date_str:
        try:
            # Parse DB date (Format often YYYY-MM-DD)
            record_date = datetime.strptime(date_str, "%Y-%m-%d")
            
            # Calculate target date based on task execution time
            task_date = datetime.fromtimestamp(task_start_ts)
            
            # Simple 3 month add: roughly 90 days
            target_date = task_date + timedelta(days=90)
            
            delta = abs((record_date - target_date).days)
            
            if delta <= 10: # Allow reasonable buffer for "3 months" interpretation
                score += 15
                feedback_log.append(f"✅ Close Date is correct (~3 months out: {date_str}).")
            else:
                feedback_log.append(f"❌ Close Date mismatch. Expected ~{target_date.strftime('%Y-%m-%d')}, got {date_str} (Diff: {delta} days).")
        except Exception as e:
            feedback_log.append(f"⚠️ Date parsing error: {str(e)}")
    else:
        feedback_log.append("❌ Close Date not set.")

    # CRITERION 6: Context/Description (15 pts)
    desc = record.get('description', '').lower()
    if "oak trees" in desc:
        score += 15
        feedback_log.append("✅ Description contains required details ('oak trees').")
    else:
        feedback_log.append("❌ Description missing required context about 'oak trees'.")

    # Final Pass Check
    # Threshold: 80 points. 
    # Must have found record, correct BP, and reasonably correct financials.
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_log)
    }