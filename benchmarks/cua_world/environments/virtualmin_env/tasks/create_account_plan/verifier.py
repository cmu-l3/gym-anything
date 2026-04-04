#!/usr/bin/env python3
"""
Verifier for create_account_plan task.
Checks if a Virtualmin hosting plan was created with specific resource limits
and applied to a target domain.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_virtualmin_multiline(text):
    """
    Parses Virtualmin 'list-plans --multiline' output.
    Returns a dict keyed by plan name, containing dict of properties.
    """
    plans = {}
    current_plan = None
    
    for line in text.splitlines():
        if not line.strip():
            continue
            
        # Lines starting with no space are plan names (usually)
        if not line.startswith(' ') and not line.startswith('\t'):
            current_plan = line.strip()
            plans[current_plan] = {}
        elif current_plan:
            # Property lines are indented
            parts = line.split(':', 1)
            if len(parts) == 2:
                key = parts[0].strip().lower()
                val = parts[1].strip()
                plans[current_plan][key] = val
                
    return plans

def parse_size_to_gb(value_str):
    """
    Parses a size string (bytes, blocks, or human readable) to GB.
    Virtualmin CLI often outputs raw bytes or 1k blocks depending on version.
    We'll try to handle common formats.
    """
    value_str = str(value_str).lower().replace(',', '')
    
    # Try regex for units
    if 'gb' in value_str:
        return float(re.search(r'([0-9.]+)', value_str).group(1))
    elif 'mb' in value_str:
        return float(re.search(r'([0-9.]+)', value_str).group(1)) / 1024
    elif 'tb' in value_str:
        return float(re.search(r'([0-9.]+)', value_str).group(1)) * 1024
        
    # If raw number, assume bytes if huge, or blocks if medium?
    # Virtualmin 'quota' field is usually 1k blocks in CLI output.
    # Bandwidth is usually bytes.
    try:
        val = float(value_str)
        # Heuristic: 10GB is ~10^10 bytes or ~10^7 blocks
        if val > 1000000000: # Likely bytes
            return val / (1024**3)
        else: # Likely 1k blocks (standard for quotas)
            return val / (1024*1024)
    except:
        return 0

def verify_create_account_plan(traj, env_info, task_info):
    """
    Verifies the account plan creation and assignment.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # 1. Load exported data
    result_json = {}
    plans_text = ""
    domain_text = ""
    
    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            # Load JSON result
            copy_from_env("/tmp/task_result.json", os.path.join(tmpdir, "result.json"))
            with open(os.path.join(tmpdir, "result.json")) as f:
                result_json = json.load(f)
                
            # Load Plans text
            copy_from_env("/tmp/task_plans.txt", os.path.join(tmpdir, "plans.txt"))
            with open(os.path.join(tmpdir, "plans.txt")) as f:
                plans_text = f.read()
                
            # Load Domain text
            copy_from_env("/tmp/task_domain.txt", os.path.join(tmpdir, "domain.txt"))
            with open(os.path.join(tmpdir, "domain.txt")) as f:
                domain_text = f.read()
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task data: {str(e)}"}

    # 2. Check basic existence
    if result_json.get("plan_existed_before"):
        return {"passed": False, "score": 0, "feedback": "Anti-gaming: Plan 'Business Pro' existed before task start."}
    
    if not result_json.get("plan_exists_now"):
        return {"passed": False, "score": 0, "feedback": "Plan 'Business Pro' was not created."}

    # 3. Parse and Verify Plan Limits
    plans = parse_virtualmin_multiline(plans_text)
    target_plan = plans.get("Business Pro")
    
    if not target_plan:
        # Fallback check: sometimes casing might differ slightly
        for p in plans:
            if p.lower() == "business pro":
                target_plan = plans[p]
                break
    
    if not target_plan:
        return {"passed": False, "score": 0, "feedback": "Could not parse details for 'Business Pro'."}

    score = 15 # Base score for existence
    feedback = ["Plan created."]
    
    metadata = task_info.get("metadata", {}).get("limits", {})
    
    # Check Disk Quota (10 GB)
    # Virtualmin key is usually "quota" or "server quota"
    quota_val = target_plan.get("quota") or target_plan.get("server quota", "0")
    if quota_val == "Unlimited":
        feedback.append("Disk quota is Unlimited (expected 10GB).")
    else:
        # Note: quota in list-plans is often in blocks (1k)
        # 10GB = 10,485,760 blocks
        # Let's handle generic conversion with tolerance
        # 10GB +/- 10%
        gb = parse_size_to_gb(quota_val)
        # Adjust logic: parse_size_to_gb assumes blocks for small numbers.
        # But if the string literally says "10.00 GiB", parse handles it.
        # If it's raw "10485760", it's blocks -> ~10GB.
        if 9.0 <= gb <= 11.0:
            score += 10
            feedback.append("Disk quota correct.")
        else:
            feedback.append(f"Disk quota incorrect ({gb:.2f} GB detected).")

    # Check Admin Quota (20 GB)
    admin_quota = target_plan.get("admin quota") or target_plan.get("administration user quota", "0")
    if 18.0 <= parse_size_to_gb(admin_quota) <= 22.0:
        score += 5
        feedback.append("Admin quota correct.")
    else:
        feedback.append("Admin quota incorrect.")

    # Check Bandwidth (100 GB)
    bw = target_plan.get("bandwidth limit") or target_plan.get("bandwidth", "0")
    if 90.0 <= parse_size_to_gb(bw) <= 110.0:
        score += 10
        feedback.append("Bandwidth correct.")
    else:
        feedback.append(f"Bandwidth incorrect (detected {parse_size_to_gb(bw):.2f} GB).")

    # Check Counts (Exact matches)
    # Keys might vary slightly in formatting
    def check_int(key_candidates, expected, points, name):
        val = 0
        for k in key_candidates:
            if k in target_plan:
                try:
                    val = int(target_plan[k])
                    break
                except: pass
        if val == expected:
            return points, f"{name} correct."
        return 0, f"{name} incorrect (found {val}, expected {expected})."

    s, f = check_int(["maximum databases", "max databases"], metadata.get("max_dbs", 10), 10, "Max DBs")
    score += s; feedback.append(f)
    
    s, f = check_int(["maximum mailboxes", "maximum users", "max mail/ftp users"], metadata.get("max_users", 100), 10, "Max Users")
    score += s; feedback.append(f)
    
    s, f = check_int(["maximum aliases", "max email aliases"], metadata.get("max_aliases", 200), 5, "Max Aliases")
    score += s; feedback.append(f)

    s, f = check_int(["maximum virtual servers", "max sub-servers"], metadata.get("max_subservers", 10), 5, "Max Sub-servers")
    score += s; feedback.append(f)

    s, f = check_int(["maximum alias domains", "max alias servers"], metadata.get("max_aliasdoms", 5), 5, "Max Alias Domains")
    score += s; feedback.append(f)

    # Check Features (Simple string search in raw plan output usually easier, but let's try parsed keys)
    # Virtualmin output for features is often "Features: web, dns, mail..."
    features_found = 0
    required_features = ["web", "ssl", "dns", "mail", "mysql", "webmin", "logrotate"]
    # Re-parse raw plan text block to find features line specifically for this plan
    plan_block = ""
    recording = False
    for line in plans_text.splitlines():
        if line.strip() == "Business Pro":
            recording = True
        elif recording and not line.startswith(" "):
            recording = False
        if recording:
            plan_block += line + "\n"
            
    for feat in required_features:
        if feat in plan_block.lower():
            features_found += 1
            
    if features_found >= len(required_features):
        score += 10
        feedback.append("All features enabled.")
    else:
        feedback.append(f"Missing some features ({features_found}/{len(required_features)} found).")

    # 4. Verify Application to Domain (15 pts)
    # Check domain_text for "Plan: Business Pro"
    domain_plan_applied = False
    for line in domain_text.splitlines():
        if "plan:" in line.lower() and "business pro" in line.lower():
            domain_plan_applied = True
            break
            
    if domain_plan_applied:
        score += 15
        feedback.append("Plan correctly applied to acmecorp.test.")
    else:
        feedback.append("Plan NOT applied to acmecorp.test.")

    return {
        "passed": score >= 60 and result_json.get("plan_exists_now") and domain_plan_applied,
        "score": score,
        "feedback": " ".join(feedback)
    }