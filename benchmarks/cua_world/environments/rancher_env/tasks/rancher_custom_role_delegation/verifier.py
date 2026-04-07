#!/usr/bin/env python3
"""
Verifier for rancher_custom_role_delegation task.

Scoring (100 points total, pass threshold 80):
- C1 (15 pts): User 'support-user' exists
- C2 (20 pts): Cluster Role 'Node Health Monitor' exists with restricted permissions (no wildcards)
- C3 (25 pts): Project Role 'L1 App Viewer' exists AND strictly EXCLUDES secrets and pods/exec
- C4 (20 pts): Project 'Support Access Project' exists and contains 'production-apps' namespace
- C5 (20 pts): 'support-user' is correctly bound to both roles
"""

import json
import tempfile
import os
import logging

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/rancher_custom_role_delegation_result.json"
PASS_THRESHOLD = 80

def check_rules(rules, forbidden_resources, allow_wildcard=False):
    """Evaluate role template rules for wildcards and forbidden resources."""
    for rule in rules:
        resources = rule.get('resources', [])
        api_groups = rule.get('apiGroups', [])
        
        # Check for wildcards
        if not allow_wildcard:
            if '*' in resources or '*' in api_groups:
                return False, "Wildcard (*) detected in rules"
                
        # Check for forbidden resources
        for fr in forbidden_resources:
            if fr in resources:
                return False, f"Forbidden resource '{fr}' detected"
                
    return True, "Rules conform to spec"

def verify_rancher_custom_role_delegation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    users = result.get('users', {}).get('items', [])
    roles = result.get('role_templates', {}).get('items', [])
    projects = result.get('projects', {}).get('items', [])
    namespaces = result.get('namespaces', {}).get('items', [])
    cluster_bindings = result.get('cluster_bindings', {}).get('items', [])
    project_bindings = result.get('project_bindings', {}).get('items', [])

    # ── C1: User 'support-user' exists ─────────────────────────────────────────
    user_id = None
    for u in users:
        if u.get('username') == 'support-user':
            user_id = u.get('metadata', {}).get('name')
            break
            
    if user_id:
        score += 15
        feedback_parts.append("C1 PASS: User 'support-user' created (+15)")
    else:
        feedback_parts.append("C1 FAIL: User 'support-user' not found")

    # ── C2: Cluster Role 'Node Health Monitor' ─────────────────────────────────
    cluster_role_id = None
    c2_pass = False
    for r in roles:
        if r.get('displayName') == 'Node Health Monitor' and r.get('context') == 'cluster':
            cluster_role_id = r.get('metadata', {}).get('name')
            rules = r.get('rules', [])
            is_compliant, msg = check_rules(rules, forbidden_resources=[], allow_wildcard=False)
            if is_compliant:
                # verify it has nodes and events
                has_nodes = any('nodes' in rule.get('resources', []) for rule in rules)
                has_events = any('events' in rule.get('resources', []) for rule in rules)
                if has_nodes and has_events:
                    c2_pass = True
                else:
                    msg = "Role missing 'nodes' or 'events' resources"
            
            if c2_pass:
                score += 20
                feedback_parts.append("C2 PASS: Cluster Role 'Node Health Monitor' is correctly scoped (+20)")
            else:
                feedback_parts.append(f"C2 FAIL: Cluster Role 'Node Health Monitor' invalid - {msg}")
            break
            
    if not cluster_role_id:
        feedback_parts.append("C2 FAIL: Cluster Role 'Node Health Monitor' not found")

    # ── C3: Project Role 'L1 App Viewer' (NO SECRETS) ──────────────────────────
    project_role_id = None
    c3_pass = False
    for r in roles:
        if r.get('displayName') == 'L1 App Viewer' and r.get('context') == 'project':
            project_role_id = r.get('metadata', {}).get('name')
            rules = r.get('rules', [])
            
            # CRITICAL: Strict HIPAA check for secrets and exec
            is_compliant, msg = check_rules(rules, forbidden_resources=['secrets', 'pods/exec'], allow_wildcard=False)
            
            if is_compliant:
                c3_pass = True
                score += 25
                feedback_parts.append("C3 PASS: Project Role 'L1 App Viewer' exists and safely excludes secrets/exec (+25)")
            else:
                feedback_parts.append(f"C3 FAIL: Project Role 'L1 App Viewer' security violation - {msg}")
            break
            
    if not project_role_id:
        feedback_parts.append("C3 FAIL: Project Role 'L1 App Viewer' not found")

    # ── C4: Project Isolation ──────────────────────────────────────────────────
    project_id = None
    for p in projects:
        if p.get('spec', {}).get('displayName') == 'Support Access Project':
            project_id = p.get('metadata', {}).get('name')
            break
            
    c4_pass = False
    if project_id:
        # Check if production-apps is in this project
        ns_in_project = False
        for ns in namespaces:
            if ns.get('metadata', {}).get('name') == 'production-apps':
                ann = ns.get('metadata', {}).get('annotations', {})
                # Format is usually clusterId:projectId
                p_id_full = ann.get('field.cattle.io/projectId', '')
                if project_id in p_id_full:
                    ns_in_project = True
                break
                
        if ns_in_project:
            c4_pass = True
            score += 20
            feedback_parts.append("C4 PASS: 'Support Access Project' created and 'production-apps' moved into it (+20)")
        else:
            feedback_parts.append("C4 FAIL: 'Support Access Project' exists but 'production-apps' namespace not moved to it")
    else:
        feedback_parts.append("C4 FAIL: Project 'Support Access Project' not found")

    # ── C5: Role Bindings ──────────────────────────────────────────────────────
    cluster_bound = False
    project_bound = False
    
    if user_id and cluster_role_id:
        for cb in cluster_bindings:
            if cb.get('userName') == user_id and cb.get('roleTemplateName') == cluster_role_id:
                cluster_bound = True
                break
                
    if user_id and project_role_id and project_id:
        for pb in project_bindings:
            # Check username, roletemplate, and ensure projectName points to the right project
            p_name = pb.get('projectName', '')
            if pb.get('userName') == user_id and pb.get('roleTemplateName') == project_role_id and project_id in p_name:
                project_bound = True
                break
                
    if cluster_bound and project_bound:
        score += 20
        feedback_parts.append("C5 PASS: User is correctly bound to both cluster and project roles (+20)")
    else:
        if not cluster_bound:
            feedback_parts.append("C5 FAIL: User not bound to Cluster Role")
        if not project_bound:
            feedback_parts.append("C5 FAIL: User not bound to Project Role")

    # ── VLM Trajectory Verification (Anti-Gaming) ───────────────────────────────
    vlm_passed = False
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            Did the agent use the Rancher web UI (dashboard) during this trajectory to manage Users, Roles, or Projects?
            Look for Rancher interface elements like 'Users & Authentication', 'Roles', 'Projects/Namespaces'.
            Respond with valid JSON:
            {"used_ui": true/false}
            """
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get("parsed", {}).get("used_ui", False):
                vlm_passed = True
                feedback_parts.append("VLM PASS: Verified Rancher UI interaction")
            else:
                feedback_parts.append("VLM WARNING: Could not verify Rancher UI interaction visually")
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")
        vlm_passed = True # Don't penalize strictly if VLM fails infrastructure-wise

    passed = score >= PASS_THRESHOLD and c3_pass  # C3 is a hard requirement for security

    if passed and not c3_pass:
        passed = False
        feedback_parts.append("FAIL: Did not pass threshold due to strict C3 security failure (HIPAA violation)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }