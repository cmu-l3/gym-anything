#!/usr/bin/env python3
"""
Verifier for remediate_accessibility_violations task.

Requirements:
1. Touch Target Size: btn_login, et_email, et_password height >= 48dp (30 pts)
2. Content Description: img_logo has description pointing to strings.xml (25 pts)
3. Autofill Hints: et_email has autofillHints and inputType (25 pts)
4. Contrast: tv_forgot_pass color is black/dark (10 pts)
5. Build Success: Project builds (10 pts)
"""

import json
import logging
import os
import re
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        logger.debug("Could not read JSON %s: %s", container_path, exc)
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def parse_dimension(dim_str):
    """Parses '48dp', '@dimen/...', or 'wrap_content' into a comparable value."""
    if not dim_str:
        return 0
    if dim_str == "match_parent":
        return 9999 # Assume compliant for container checks, but context dependent
    if dim_str == "wrap_content":
        return 0 # Cannot determine statically, usually flagged as warning in a11y tools if content is small
    
    # Parse '48dp' -> 48
    match = re.match(r'^(\d+)(dp|sp|px)?$', dim_str)
    if match:
        return int(match.group(1))
    return 0

def check_color_contrast(color_str):
    """Checks if color is sufficiently dark (black)."""
    if not color_str:
        return False
    
    # Accept standard black references
    if color_str in ["@android:color/black", "#000000", "#000"]:
        return True
        
    # Check hex values
    if color_str.startswith("#"):
        try:
            hex_val = color_str.lstrip('#')
            if len(hex_val) == 6:
                r, g, b = tuple(int(hex_val[i:i+2], 16) for i in (0, 2, 4))
                # Simple check: Is it reasonably dark? (Y < 128)
                # Rec. 601 luma
                luma = 0.299 * r + 0.587 * g + 0.114 * b
                return luma < 50 # Strict black/dark grey
            elif len(hex_val) == 3:
                # Expand #000
                r = int(hex_val[0]*2, 16)
                g = int(hex_val[1]*2, 16)
                b = int(hex_val[2]*2, 16)
                luma = 0.299 * r + 0.587 * g + 0.114 * b
                return luma < 50
        except ValueError:
            pass
            
    return False

def verify_remediate_accessibility(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    layout_content = result.get("layout_content", "")
    strings_content = result.get("strings_content", "")
    build_success = result.get("build_success", False)
    
    score = 0
    feedback = []
    
    if not layout_content:
        return {"passed": False, "score": 0, "feedback": "Layout file not found or empty."}

    # Parse XML
    try:
        # Remove namespaces for easier findall if needed, or register them
        # Android XML usually has namespaces. simpler to just ignore them for this check
        # or use local-name() in xpath if python supported it well.
        # We'll just strip namespaces for robust parsing of attributes
        clean_layout = re.sub(r' xmlns:android="[^"]+"', '', layout_content)
        clean_layout = re.sub(r' xmlns:app="[^"]+"', '', clean_layout)
        # Also need to handle attribute prefixes 'android:' -> ''
        # This is a bit hacky but efficient for simple verification
        clean_layout = clean_layout.replace('android:', '')
        clean_layout = clean_layout.replace('app:', '')
        
        root = ET.fromstring(clean_layout)
    except ET.ParseError as e:
        return {"passed": False, "score": 0, "feedback": f"XML Parse Error: {e}"}

    # Helper to find view by ID (id is now just 'id' due to cleaning)
    def find_view_by_id(view_id_name):
        # Look for @+id/name
        target = f"@+id/{view_id_name}"
        for elem in root.iter():
            if elem.get('id') == target:
                return elem
        return None

    # ---------------------------------------------------------
    # 1. Touch Target Size (30 pts)
    # Check btn_login, et_email, et_password
    # ---------------------------------------------------------
    target_views = ["btn_login", "et_email", "et_password"]
    size_passed = 0
    size_feedback = []
    
    for v_name in target_views:
        elem = find_view_by_id(v_name)
        if elem is not None:
            h = elem.get('layout_height')
            min_h = elem.get('minHeight')
            
            height_val = parse_dimension(h)
            min_height_val = parse_dimension(min_h)
            
            if height_val >= 48 or min_height_val >= 48:
                size_passed += 1
            else:
                size_feedback.append(f"{v_name} too small")
        else:
            size_feedback.append(f"{v_name} not found")
            
    if size_passed == 3:
        score += 30
        feedback.append("Touch targets compliant (30/30)")
    elif size_passed > 0:
        partial = size_passed * 10
        score += partial
        feedback.append(f"Partial touch targets fix ({partial}/30): {', '.join(size_feedback)}")
    else:
        feedback.append("Touch targets not fixed (0/30)")

    # ---------------------------------------------------------
    # 2. Content Description (25 pts)
    # Check img_logo
    # ---------------------------------------------------------
    logo = find_view_by_id("img_logo")
    desc_ok = False
    
    if logo is not None:
        cd = logo.get('contentDescription')
        if cd:
            if cd.startswith("@string/"):
                # Verify string exists
                res_name = cd.replace("@string/", "")
                if f'name="{res_name}"' in strings_content:
                    desc_ok = True
                    feedback.append("Content description correct (25/25)")
                else:
                    feedback.append("Content description points to missing string (5/25)")
                    score += 5
            else:
                feedback.append("Content description hardcoded (warning) (15/25)")
                score += 15
                desc_ok = True # Partial credit for just adding it
        else:
            feedback.append("Missing content description on logo (0/25)")
    
    if desc_ok and score < 55: # If not already added partial
        score += 25

    # ---------------------------------------------------------
    # 3. Autofill Hints (25 pts)
    # Check et_email
    # ---------------------------------------------------------
    email = find_view_by_id("et_email")
    autofill_ok = False
    input_type_ok = False
    
    if email is not None:
        hints = email.get('autofillHints')
        itype = email.get('inputType')
        
        if hints and ("email" in hints.lower()):
            autofill_ok = True
        
        if itype and ("textEmailAddress" in itype):
            input_type_ok = True
            
    if autofill_ok and input_type_ok:
        score += 25
        feedback.append("Autofill configuration correct (25/25)")
    elif autofill_ok or input_type_ok:
        score += 10
        feedback.append("Partial autofill fix (10/25)")
    else:
        feedback.append("Autofill/InputType missing on email (0/25)")

    # ---------------------------------------------------------
    # 4. Contrast (10 pts)
    # Check tv_forgot_pass
    # ---------------------------------------------------------
    tv = find_view_by_id("tv_forgot_pass")
    contrast_ok = False
    
    if tv is not None:
        color = tv.get('textColor')
        if check_color_contrast(color):
            contrast_ok = True
            
    if contrast_ok:
        score += 10
        feedback.append("Text contrast fixed (10/10)")
    else:
        feedback.append("Text contrast still low (0/10)")

    # ---------------------------------------------------------
    # 5. Build Success (10 pts)
    # ---------------------------------------------------------
    if build_success:
        score += 10
        feedback.append("Project builds successfully (10/10)")
    else:
        feedback.append("Build failed (0/10)")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback)
    }