#!/usr/bin/env python3
"""
Verifier for the repair_sqlalchemy_orm_layer task.

Evaluates static codebase fixes for 5 distinct SQLAlchemy ORM issues:
1. N+1 Queries (eager loading)
2. Cascade deletion (delete-orphan)
3. Self-referential models (remote_side)
4. Decimal/Numeric column precision
5. SQL side aggregation (func.sum)
"""

import os
import json
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_n_plus_one(repo_src):
    if re.search(r'(?:selectinload|joinedload|subqueryload)', repo_src):
        return True, "repository.py correctly uses eager loading for Artist.albums (N+1 fixed)"
    return False, "repository.py still has N+1 query problem for Artist.albums (missing eager loading)"

def check_cascade_delete(models_src):
    if re.search(r'cascade\s*=\s*["\']all,\s*delete(?:-orphan)?["\']', models_src):
        return True, "models.py correctly configures cascade deletion for Album tracks"
    return False, "models.py is missing or incorrectly configures cascade deletion for Album tracks"

def check_self_referential(models_src):
    if re.search(r'remote_side\s*=\s*(\[?\s*(?:Employee\.)?EmployeeId\s*\]?|["\'](?:Employee\.)?EmployeeId["\'])', models_src):
        return True, "models.py correctly configures remote_side for Employee manager relationship"
    return False, "models.py is missing remote_side configuration for Employee"

def check_financial_precision(models_src):
    if re.search(r'UnitPrice\s*=\s*Column\s*\(\s*(?:Numeric|DECIMAL)', models_src):
        return True, "models.py uses precise Numeric/DECIMAL type for UnitPrice"
    return False, "models.py still uses Float for UnitPrice"

def check_sql_aggregation(repo_src):
    if re.search(r'func\.sum\s*\(', repo_src):
        return True, "repository.py aggregates duration natively in SQL using func.sum"
    return False, "repository.py does not use func.sum for duration aggregation"


def verify_orm_layer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='orm_verify_')
    local_result = os.path.join(temp_dir, "orm_task_result.json")

    try:
        copy_from_env("/tmp/orm_task_result.json", local_result)
        with open(local_result, 'r') as f:
            data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy or read result file: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not access result file: {str(e)}"}
    finally:
        if os.path.exists(local_result):
            os.unlink(local_result)
        os.rmdir(temp_dir)

    models_src = data.get("files", {}).get("models.py", "")
    repo_src = data.get("files", {}).get("repository.py", "")

    score = 0
    feedback = []

    # Anti-gaming check: File modification timestamps
    models_mod = data.get("models_modified", False)
    repo_mod = data.get("repo_modified", False)
    
    if not (models_mod or repo_mod):
        feedback.append("[-] WARNING: Files were not modified during the task duration. Ensure you save changes.")

    # 1. N+1 Queries (20 pts)
    n1_pass, n1_msg = check_n_plus_one(repo_src)
    if n1_pass:
        score += 20
        feedback.append(f"[+] {n1_msg} (20/20)")
    else:
        feedback.append(f"[-] {n1_msg} (0/20)")

    # 2. Cascade Deletion (20 pts)
    cd_pass, cd_msg = check_cascade_delete(models_src)
    if cd_pass:
        score += 20
        feedback.append(f"[+] {cd_msg} (20/20)")
    else:
        feedback.append(f"[-] {cd_msg} (0/20)")

    # 3. Self-Referential FK (20 pts)
    sr_pass, sr_msg = check_self_referential(models_src)
    if sr_pass:
        score += 20
        feedback.append(f"[+] {sr_msg} (20/20)")
    else:
        feedback.append(f"[-] {sr_msg} (0/20)")

    # 4. Financial Precision (20 pts)
    fp_pass, fp_msg = check_financial_precision(models_src)
    if fp_pass:
        score += 20
        feedback.append(f"[+] {fp_msg} (20/20)")
    else:
        feedback.append(f"[-] {fp_msg} (0/20)")

    # 5. SQL Aggregation (20 pts)
    sa_pass, sa_msg = check_sql_aggregation(repo_src)
    if sa_pass:
        score += 20
        feedback.append(f"[+] {sa_msg} (20/20)")
    else:
        feedback.append(f"[-] {sa_msg} (0/20)")

    # VLM Trajectory Evidence Check (Optional robust mechanism)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        if frames and final:
            vlm_res = query_vlm(
                images=frames + [final],
                prompt="Did the user actively interact with and edit Python files like models.py or repository.py in VS Code?"
            )
            vlm_passed = vlm_res.get("parsed", {}).get("answer", True) if isinstance(vlm_res.get("parsed"), dict) else True
            if not vlm_passed:
                feedback.append("[-] VLM indicates lack of trajectory evidence for code modification.")

    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 60)
    passed = score >= pass_threshold and (models_mod or repo_mod)

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }