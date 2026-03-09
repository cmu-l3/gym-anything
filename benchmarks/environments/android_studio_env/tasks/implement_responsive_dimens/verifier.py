#!/usr/bin/env python3
"""
Verifier for implement_responsive_dimens task.

Checks:
1. activity_profile.xml refactored to remove hardcoded values (30 pts)
2. values/dimens.xml contains extracted values (20 pts)
3. values-sw600dp/dimens.xml exists (10 pts)
4. values-sw600dp/dimens.xml contains overrides (20 pts)
5. Overrides are effectively larger than base values (10 pts)
6. Build success (10 pts)
"""

import json
import logging
import re
import tempfile
import os
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r") as fh:
            return json.load(fh)
    except Exception:
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def extract_dimens(xml_content):
    """Parse XML content to extract dimen names and values."""
    dimens = {}
    try:
        root = ET.fromstring(xml_content)
        for dimen in root.findall('dimen'):
            name = dimen.get('name')
            value = dimen.text
            if name and value:
                dimens[name] = value
    except ET.ParseError:
        pass
    return dimens

def parse_dimen_value(value_str):
    """Convert '16dp' to float 16.0."""
    match = re.match(r'(\d+(\.\d+)?)', value_str)
    if match:
        return float(match.group(1))
    return 0.0

def verify_implement_responsive_dimens(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error"}

    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    score = 0
    feedback = []
    
    layout_content = result.get('layout_content', '')
    base_dimens_content = result.get('base_dimens_content', '')
    tablet_dimens_content = result.get('tablet_dimens_content', '')
    
    # 1. Layout Refactoring (30 pts)
    # Check for hardcoded values (BAD)
    hardcoded_patterns = [r'"\d+dp"', r'"\d+sp"']
    found_hardcoded = any(re.search(p, layout_content) for p in hardcoded_patterns)
    
    # Check for dimen references (GOOD)
    found_refs = bool(re.search(r'"@dimen/[\w_]+"', layout_content))
    
    if found_refs and not found_hardcoded:
        score += 30
        feedback.append("Layout successfully refactored (30/30)")
    elif found_refs and found_hardcoded:
        score += 15
        feedback.append("Layout partially refactored (some hardcoded values remain) (15/30)")
    else:
        feedback.append("Layout not refactored (0/30)")

    # 2. Base Dimens (20 pts)
    base_dimens = extract_dimens(base_dimens_content)
    if len(base_dimens) >= 3:
        score += 20
        feedback.append(f"Base dimensions created ({len(base_dimens)} items) (20/20)")
    elif len(base_dimens) > 0:
        score += 10
        feedback.append("Some base dimensions created (10/20)")
    else:
        feedback.append("No base dimensions found (0/20)")

    # 3. Tablet Directory (10 pts)
    if result.get('tablet_dir_exists'):
        score += 10
        feedback.append("Tablet directory created (10/10)")
    else:
        feedback.append("Tablet directory missing (0/10)")

    # 4. Tablet Dimens & 5. Responsive Logic (30 pts combined)
    tablet_dimens = extract_dimens(tablet_dimens_content)
    
    if len(tablet_dimens) > 0:
        score += 20
        feedback.append("Tablet dimensions file created (20/20)")
        
        # Check values are larger
        larger_count = 0
        total_checked = 0
        for name, t_val in tablet_dimens.items():
            if name in base_dimens:
                b_val_num = parse_dimen_value(base_dimens[name])
                t_val_num = parse_dimen_value(t_val)
                total_checked += 1
                if t_val_num > b_val_num:
                    larger_count += 1
        
        if total_checked > 0 and larger_count == total_checked:
            score += 10
            feedback.append("All tablet dimensions are larger (Responsive logic correct) (10/10)")
        elif larger_count > 0:
            score += 5
            feedback.append("Some tablet dimensions are larger (5/10)")
        else:
            feedback.append("Tablet dimensions are not larger than base (0/10)")
    else:
        feedback.append("Tablet dimensions empty or missing (0/30)")

    # 6. Build Success (10 pts)
    if result.get('build_success'):
        score += 10
        feedback.append("Build success (10/10)")
    else:
        feedback.append("Build failed (0/10)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }