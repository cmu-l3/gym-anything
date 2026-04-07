#!/usr/bin/env python3
"""
Verifier for deprecate_legacy_requirements task.

Criteria:
1. Identify all requirements with "T-800" (based on Ground Truth from setup).
2. Verify 'Priority' attribute is set to 'Low' for these requirements.
3. Verify 'text' (Description) starts with "[DEPRECATED]" (case insensitive).
4. Verify non-target requirements were NOT modified (anti-gaming).
5. Verify project was saved (file timestamp).
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deprecate_legacy_requirements(traj, env_info, task_info):
    """Verify that legacy T-800 requirements are properly deprecated."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve Result JSON to get paths
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    srs_path = result_data.get("srs_path", "")
    ground_truth_path = result_data.get("ground_truth_path", "/tmp/legacy_targets.json")
    srs_modified = result_data.get("srs_modified", False)

    if not srs_path or not srs_modified:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Project was not saved (SRS file not modified or not found)."
        }

    # 2. Retrieve SRS and Ground Truth files
    temp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env(srs_path, temp_srs.name)
        copy_from_env(ground_truth_path, temp_gt.name)
        
        with open(temp_srs.name, 'r') as f:
            srs_data = json.load(f)
            
        with open(temp_gt.name, 'r') as f:
            target_ids = set(json.load(f))
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve validation files: {e}"}
    finally:
        if os.path.exists(temp_srs.name): os.unlink(temp_srs.name)
        if os.path.exists(temp_gt.name): os.unlink(temp_gt.name)

    # 3. Analyze Requirements
    score = 0
    feedback_parts = []
    
    # Helper to clean text (remove HTML)
    def clean_text(text):
        if not text: return ""
        text = re.sub(r'<[^>]+>', '', str(text)) # strip tags
        text = text.replace('&nbsp;', ' ')
        return text.strip()

    # Helper to traverse JSON
    req_map = {}
    def map_reqs(node):
        if isinstance(node, dict):
            if 'id' in node:
                req_map[node['id']] = node
            if 'children' in node and isinstance(node['children'], list):
                for child in node['children']:
                    map_reqs(child)
        elif isinstance(node, list):
            for item in node:
                map_reqs(item)

    # Handle SRS structure
    root = srs_data.get('data', srs_data.get('children', []))
    map_reqs(root)

    if not target_ids:
        return {"passed": False, "score": 0, "feedback": "Setup Error: No ground truth targets defined."}

    # Scoring Logic
    # 60% for correct targets (30% Priority, 30% Text)
    # 30% for preserving non-targets
    # 10% for saving file (already checked implicit by existence, but added to score)
    
    total_targets = len(target_ids)
    targets_prio_ok = 0
    targets_text_ok = 0
    
    # Check Targets
    for tid in target_ids:
        if tid not in req_map:
            feedback_parts.append(f"Target req {tid} deleted (FAIL)")
            continue
        
        req = req_map[tid]
        
        # Check Priority (Accept 'Low', 'L', 'low', or whatever key represents Low)
        # In this project, usually key is 'Low' or 'L'
        prio = str(req.get('priority', '')).lower()
        if prio in ['low', 'l']:
            targets_prio_ok += 1
        
        # Check Text Prefix
        txt = clean_text(req.get('text', ''))
        if txt.upper().startswith('[DEPRECATED]'):
            targets_text_ok += 1
        else:
            # Debug feedback for failures
            # feedback_parts.append(f"Req {tid}: Text starts with '{txt[:20]}...'")
            pass

    # Check Non-Targets (Anti-gaming: Did they just 'Select All'?)
    non_target_errors = 0
    checked_non_targets = 0
    
    for tid, req in req_map.items():
        if tid in target_ids: continue
        
        checked_non_targets += 1
        txt = clean_text(req.get('text', ''))
        prio = str(req.get('priority', '')).lower()
        
        # If they indiscriminately changed things to DEPRECATED or Low
        if txt.upper().startswith('[DEPRECATED]'):
            non_target_errors += 1
        # Note: We don't penalize Low priority on non-targets as strict, 
        # because some might legitimately be Low. But mass text change is a clear error.

    # Calc Score
    prio_score = (targets_prio_ok / total_targets) * 30
    text_score = (targets_text_ok / total_targets) * 30
    
    # Preservation Score (30 pts)
    # Lose points proportionally to errors, capped at 0
    preservation_score = 30
    if checked_non_targets > 0:
        error_rate = non_target_errors / checked_non_targets
        # Penalty is steep: 10% error rate wipes out preservation score
        penalty = (error_rate * 10) * 30 
        preservation_score = max(0, 30 - penalty)

    score = 10 + prio_score + text_score + preservation_score # 10 pts for file save
    
    feedback_parts.append(f"Priority updates: {targets_prio_ok}/{total_targets}")
    feedback_parts.append(f"Text updates: {targets_text_ok}/{total_targets}")
    if non_target_errors > 0:
        feedback_parts.append(f"WARNING: Modified {non_target_errors} non-target requirements incorrectly")
    else:
        feedback_parts.append("Non-target requirements preserved")

    return {
        "passed": score >= 75,
        "score": round(score),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "targets_total": total_targets,
            "targets_prio_correct": targets_prio_ok,
            "targets_text_correct": targets_text_ok,
            "collateral_damage_count": non_target_errors
        }
    }