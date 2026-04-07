#!/usr/bin/env python3
"""
Verifier for historical_traffic_1924 task.

Checks:
1. Scenario directory structure (20 pts)
2. Historical curation (Model selection) (30 pts)
3. Environment settings (Date/Visibility) (15 pts)
4. Traffic placement (Validity/Quantity) (15 pts)
5. Manifest documentation (20 pts)
"""

import json
import base64
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_historical_traffic(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    forbidden_keywords = metadata.get('forbidden_keywords', [])
    preferred_keywords = metadata.get('preferred_keywords', [])
    min_vessels = metadata.get('min_vessels', 6)
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Helper to decode base64
    def decode_ini(b64_str):
        if not b64_str: return ""
        try:
            return base64.b64decode(b64_str).decode('utf-8', errors='ignore')
        except:
            return ""

    # 1. Structure Check (20 pts)
    if result.get('scenario_exists') and result.get('env_exists') and \
       result.get('own_exists') and result.get('other_exists'):
        score += 20
        feedback.append("Scenario directory and INI files created.")
    else:
        feedback.append("Missing scenario files.")
        return {"passed": False, "score": 0, "feedback": "Scenario not created correctly."}

    # 2. Environment Check (15 pts)
    env_text = decode_ini(result.get('env_content_b64'))
    
    # Check Year
    year_match = re.search(r'StartYear\s*=\s*(\d+)', env_text, re.IGNORECASE)
    if year_match and int(year_match.group(1)) == 1924:
        score += 8
        feedback.append("Year set to 1924.")
    else:
        feedback.append(f"Year incorrect (Expected 1924, found {year_match.group(1) if year_match else 'None'}).")

    # Check Visibility
    vis_match = re.search(r'VisibilityRange\s*=\s*([\d\.]+)', env_text, re.IGNORECASE)
    if vis_match:
        vis = float(vis_match.group(1))
        if vis <= 5.0:
            score += 7
            feedback.append(f"Visibility set to {vis}nm (Hazy).")
        else:
            feedback.append(f"Visibility {vis}nm is too clear for requirements (<=5.0).")
    else:
        feedback.append("VisibilityRange not found.")

    # 3. Traffic & Historical Curation Check (45 pts total)
    other_text = decode_ini(result.get('other_content_b64'))
    
    # Extract all ModelFileName entries (Bridge Command uses ModelFileName="path/to/model")
    # Also handle simpler keys if agent used them (BC is flexible)
    # The standard key is often 'ModelFileName' or just implied by directory structure if using 'Type'
    # Actually, in othership.ini, it's usually `Type(N)="ModelName"`.
    
    vessel_types = re.findall(r'Type\(\d+\)\s*=\s*"?([^"\n\r]+)"?', other_text, re.IGNORECASE)
    unique_vessels = set(vessel_types)
    count = len(unique_vessels)

    # Quantity Check (15 pts)
    if count >= min_vessels:
        score += 15
        feedback.append(f"Traffic count acceptable ({count} unique models).")
    else:
        # Partial credit
        partial = int((count / min_vessels) * 15)
        score += partial
        feedback.append(f"Traffic count low ({count}/{min_vessels}).")

    # Historical Quality Check (30 pts)
    # Deduct for modern keywords, Reward for generic/period keywords
    modern_violations = []
    period_confirmations = []
    
    for v in unique_vessels:
        v_lower = v.lower()
        if any(bad in v_lower for bad in forbidden_keywords):
            modern_violations.append(v)
        if any(good in v_lower for good in preferred_keywords):
            period_confirmations.append(v)

    if modern_violations:
        feedback.append(f"Anachronisms detected: {', '.join(modern_violations)}.")
        # Heavy penalty: 0 points for this section if ANY modern ship is found
    else:
        # If no modern violations, score based on adherence to preferred list or general plausibility
        if len(period_confirmations) >= 3:
            score += 30
            feedback.append("Vessel selection appears historically appropriate.")
        elif count > 0:
            # If they didn't match preferred keywords but also didn't trigger forbidden ones,
            # give partial credit (maybe they used models we didn't predict)
            score += 15
            feedback.append("Vessel selection is neutral (no obvious modern ships, but few confirmed period keywords).")

    # 4. Manifest Check (20 pts)
    if result.get('manifest_exists'):
        manifest_text = decode_ini(result.get('manifest_content_b64'))
        if len(manifest_text) > 50: # Arbitrary "enough text" check
            score += 20
            feedback.append("Manifest created and populated.")
        else:
            score += 10
            feedback.append("Manifest exists but is very short.")
    else:
        feedback.append("Manifest file missing.")

    # Final Pass Decision
    # Must pass Historical Check (no modern ships) and have created the scenario
    passed = (score >= 70) and (not modern_violations) and result.get('scenario_exists')

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }