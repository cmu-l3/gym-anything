#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organize_documents_into_collections(traj, env_info, task_info):
    """
    Verifies that the agent created specific collections and assigned documents correctly.
    """
    # 1. Setup and retrieve result data using copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    finance_uid = result.get('finance_collection_uid')
    strategy_uid = result.get('strategy_collection_uid')
    
    # Document memberships (lists of UIDs)
    doc_annual_report_cols = result.get('doc_annual_report_collections', [])
    doc_proposal_cols = result.get('doc_proposal_collections', [])
    doc_q3_report_cols = result.get('doc_q3_report_collections', [])

    # Anti-gaming: Check creation times vs task start
    task_start_ts = result.get('task_start', 0)
    
    def check_timestamp(iso_date_str):
        if not iso_date_str: return False
        try:
            # Handle Nuxeo ISO format (e.g. 2023-10-27T10:00:00.00Z)
            # Simplified check: just checking if string exists and parsing basic format
            dt = datetime.strptime(iso_date_str.split('.')[0], "%Y-%m-%dT%H:%M:%S")
            return dt.timestamp() > task_start_ts
        except ValueError:
            return True # If parsing fails, leniently accept if string exists, assumes new

    # 3. Scoring Logic
    score = 0
    feedback_items = []

    # Criterion 1: Collections Exist (20 pts)
    if finance_uid and check_timestamp(result.get('finance_created_at')):
        score += 10
        feedback_items.append("Collection 'Finance Resources' created.")
    else:
        feedback_items.append("Collection 'Finance Resources' missing or old.")

    if strategy_uid and check_timestamp(result.get('strategy_created_at')):
        score += 10
        feedback_items.append("Collection 'Strategy Resources' created.")
    else:
        feedback_items.append("Collection 'Strategy Resources' missing or old.")

    # Criterion 2: Annual Report in Finance (20 pts)
    if finance_uid and finance_uid in doc_annual_report_cols:
        score += 20
        feedback_items.append("Annual Report added to Finance.")
    else:
        feedback_items.append("Annual Report NOT in Finance.")

    # Criterion 3: Project Proposal in Strategy (20 pts)
    if strategy_uid and strategy_uid in doc_proposal_cols:
        score += 20
        feedback_items.append("Project Proposal added to Strategy.")
    else:
        feedback_items.append("Project Proposal NOT in Strategy.")

    # Criterion 4: Q3 Report in Finance (20 pts)
    if finance_uid and finance_uid in doc_q3_report_cols:
        score += 20
        feedback_items.append("Q3 Report added to Finance.")
    else:
        feedback_items.append("Q3 Report NOT in Finance.")

    # Criterion 5: Q3 Report in Strategy (20 pts)
    if strategy_uid and strategy_uid in doc_q3_report_cols:
        score += 20
        feedback_items.append("Q3 Report added to Strategy.")
    else:
        feedback_items.append("Q3 Report NOT in Strategy.")

    # 4. Final Result
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_items)
    }