#!/usr/bin/env python3
"""
Verifier for Normalize URL Reporting task.

Task: Configure 'TechGadgets Shop' to:
1. Exclude parameters: fbclid, gclid, session_id
2. Disable URL fragments (keep_url_fragment = 0)

Criteria:
- Target site ID must have the specific parameters in 'excluded_parameters'.
- Target site ID must have 'keep_url_fragment' == 0.
- Control site ID must NOT be modified (Wrong Target Gate).
"""

import json
import logging
import os
import tempfile
from typing import Any, Dict, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REQUIRED_PARAMS = ["fbclid", "gclid", "session_id"]

def parse_params(param_str: str) -> List[str]:
    """Parse comma/newline separated parameters into a clean list."""
    if not param_str:
        return []
    # Replace newlines with commas just in case, split, strip, lowercase
    normalized = param_str.replace('\n', ',').replace('\r', '')
    return [p.strip().lower() for p in normalized.split(',') if p.strip()]

def verify_normalize_url_reporting(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    target = result.get("target_site", {})
    control = result.get("control_site", {})
    
    score = 0
    feedback = []
    
    # ── 1. Wrong Target Gate ──────────────────────────────────────────────
    if control.get("modified", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: You modified the 'Initial Site' (Control). Only 'TechGadgets Shop' should be changed."
        }

    # ── 2. Check Excluded Parameters ──────────────────────────────────────
    current_params_str = target.get("current_params", "")
    # Remove quotes that json_escape might have added if double encoded, 
    # though valid JSON load handles normal strings. 
    # Usually Matomo stores: "fbclid,gclid" or "fbclid\ngclid"
    if current_params_str.startswith('"') and current_params_str.endswith('"'):
        current_params_str = current_params_str[1:-1]
        
    actual_params = parse_params(current_params_str)
    
    for req in REQUIRED_PARAMS:
        if req in actual_params:
            score += 20
            feedback.append(f"Parameter '{req}' excluded correctly (+20)")
        else:
            feedback.append(f"Parameter '{req}' missing from exclusion list")

    # ── 3. Check URL Fragments ────────────────────────────────────────────
    # Expect 0 (No)
    # Database might return integer 0 or string "0"
    frag_val = str(target.get("current_fragment", "1")).strip()
    
    if frag_val == "0":
        score += 20
        feedback.append("URL fragments disabled correctly (+20)")
    else:
        feedback.append(f"URL fragments setting incorrect (expected 0/No, got {frag_val})")

    # ── 4. Save Confirmation (Implicit) ───────────────────────────────────
    # If we have score > 0, it means changes were persisted to DB, so we award "Saved" points
    # Logic: If at least one setting is correct (score > 0), they successfully saved *something*.
    # We'll calculate total possible from prev steps (3*20 + 20 = 80). 
    # If score > 0, we add the final 20 for 'Configuration Saved'.
    if score > 0:
        score += 20
        feedback.append("Configuration saved successfully (+20)")
    else:
        feedback.append("No correct changes persisted to database")

    # Final tally
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }