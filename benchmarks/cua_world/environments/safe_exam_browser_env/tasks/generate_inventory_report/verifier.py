#!/usr/bin/env python3
"""
Verifier for generate_inventory_report task.

This verifier pulls the agent's generated report and the extracted ground truth 
data from the environment, and compares them programmatically to ensure precision
and accuracy.

Verification Criteria:
1. File exists and valid JSON (10 points)
2. Required structure is present (10 points)
3. Institutions array is complete & accurate (20 points)
4. User accounts array is complete & accurate (25 points)
5. Exam configurations array is complete & accurate (20 points)
6. Summary counts are mathematically correct (10 points)
7. Anti-gaming check: File created after task start (5 points)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inventory_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability unavailable."}

    score = 0
    feedback_parts = []
    
    # 1. Pull task metadata
    task_result_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("/tmp/task_result.json", task_result_path)
        with open(task_result_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {e}"}
    finally:
        if os.path.exists(task_result_path): os.unlink(task_result_path)

    report_exists = task_result.get('report_exists', False)
    created_after_start = task_result.get('created_after_start', False)

    if not report_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAILED: Target report file (~/Documents/seb_inventory_report.json) does not exist."
        }

    # 2. Pull ground truth
    gt_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("/tmp/ground_truth.json", gt_path)
        with open(gt_path, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ground truth data: {e}"}
    finally:
        if os.path.exists(gt_path): os.unlink(gt_path)

    # 3. Pull agent report
    agent_report_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    agent_report = None
    try:
        copy_from_env("/tmp/agent_report.json", agent_report_path)
        with open(agent_report_path, 'r') as f:
            agent_report = json.load(f)
        score += 10
        feedback_parts.append("Report exists and is valid JSON (+10)")
    except json.JSONDecodeError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAILED: Report file exists but contains invalid JSON formatting."
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse agent report: {e}"}
    finally:
        if os.path.exists(agent_report_path): os.unlink(agent_report_path)

    # Criterion: Required structure
    required_keys = task_info.get("metadata", {}).get("required_keys", ["institutions", "user_accounts", "exam_configurations", "summary"])
    missing_keys = [k for k in required_keys if k not in agent_report]
    
    if not missing_keys:
        score += 10
        feedback_parts.append("Correct top-level structure (+10)")
    else:
        partial = int(10 * (len(required_keys) - len(missing_keys)) / len(required_keys))
        score += partial
        feedback_parts.append(f"Missing top-level keys: {missing_keys} (+{partial})")

    # Criterion: Institutions completeness & accuracy
    db_inst = ground_truth.get('institutions', [])
    ag_inst = agent_report.get('institutions', []) if isinstance(agent_report.get('institutions'), list) else []
    
    matched_inst = sum(1 for d in db_inst if any(str(a.get('id')) == d['id'] or a.get('name') == d['name'] for a in ag_inst))
    if db_inst:
        pts = int(20 * (matched_inst / len(db_inst)))
        score += pts
        feedback_parts.append(f"Institutions: {matched_inst}/{len(db_inst)} matched (+{pts})")
    else:
        score += 20
        feedback_parts.append("Institutions: None in DB, correct (+20)")

    # Criterion: User accounts completeness & accuracy
    db_users = ground_truth.get('users', [])
    ag_users = agent_report.get('user_accounts', []) if isinstance(agent_report.get('user_accounts'), list) else []

    matched_users = sum(1 for d in db_users if any(a.get('username') == d['username'] for a in ag_users))
    if db_users:
        pts = int(25 * (matched_users / len(db_users)))
        score += pts
        feedback_parts.append(f"Users: {matched_users}/{len(db_users)} matched (+{pts})")
    else:
        score += 25
        feedback_parts.append("Users: None in DB, correct (+25)")

    # Criterion: Exam configurations completeness & accuracy
    db_configs = ground_truth.get('configs', [])
    ag_configs = agent_report.get('exam_configurations', []) if isinstance(agent_report.get('exam_configurations'), list) else []

    matched_configs = sum(1 for d in db_configs if any(str(a.get('id')) == d['id'] or a.get('name') == d['name'] for a in ag_configs))
    if db_configs:
        pts = int(20 * (matched_configs / len(db_configs)))
        score += pts
        feedback_parts.append(f"Configs: {matched_configs}/{len(db_configs)} matched (+{pts})")
    else:
        score += 20
        feedback_parts.append("Configs: None in DB, correct (+20)")

    # Criterion: Summary counts
    summary = agent_report.get('summary', {})
    pts_summary = 0
    if isinstance(summary, dict):
        if summary.get('total_institutions') == len(db_inst): pts_summary += 3
        if summary.get('total_users') == len(db_users): pts_summary += 4
        if summary.get('total_exam_configurations') == len(db_configs): pts_summary += 3
        
    score += pts_summary
    feedback_parts.append(f"Summary counts matched (+{pts_summary})")

    # Anti-gaming: Created after start
    if created_after_start:
        score += 5
        feedback_parts.append("File created after task start (+5)")
    else:
        feedback_parts.append("WARNING: File predates task start (0)")

    # Final determination
    passed = score >= 60 and report_exists and not missing_keys

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }