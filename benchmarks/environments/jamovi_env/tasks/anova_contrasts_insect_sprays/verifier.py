#!/usr/bin/env python3
"""
Verifier for anova_contrasts_insect_sprays task.

Criteria:
1. OMV file created and valid (contains ANOVA analysis).
2. Factor levels reordered correctly (F is first/reference).
3. "Simple" contrasts selected.
4. Report file contains correct t-statistic value (-9.12 ± 0.1).

The ground truth calculation for InsectSprays (count ~ spray):
  Reference: F (mean=16.667, n=12)
  Comparison: C (mean=2.083, n=12)
  ANOVA MSE (Mean Square Error) ≈ 15.39
  Standard Error of Difference = sqrt(MSE * (1/n1 + 1/n2)) = sqrt(15.39 * (1/12 + 1/12)) ≈ 1.60
  Difference = 2.083 - 16.667 = -14.584
  t-statistic = -14.584 / 1.60 ≈ -9.11
"""

import json
import os
import zipfile
import tempfile
import math
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth values calculated from R's InsectSprays
# lm(count ~ relevel(spray, ref="F"), data=InsectSprays)
EXPECTED_T_VALUE = -9.116
TOLERANCE = 0.15  # Allow small rounding differences

def verify_anova_contrasts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Verify OMV file structure (it's a ZIP)
    omv_exists = result.get("omv_exists", False)
    omv_valid = False
    factor_reordered = False
    contrast_set = False
    
    if omv_exists and result.get("omv_created_during_task", False):
        score += 10
        feedback_parts.append("OMV file created")
        
        # Download OMV to inspect contents
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
        try:
            copy_from_env("/home/ga/Documents/Jamovi/Spray_Contrasts.omv", temp_omv.name)
            
            if zipfile.is_zipfile(temp_omv.name):
                with zipfile.ZipFile(temp_omv.name, 'r') as z:
                    # Jamovi saves analysis definitions in JSON files (index 0, 1, etc.)
                    # We look for the one defining the ANOVA
                    # Also metadata.json might contain variable definitions
                    
                    # Check variable order in metadata
                    if "meta" in z.namelist() or "metadata.json" in z.namelist():
                        # Recent Jamovi versions structure varies, but let's check analysis options first
                        pass
                    
                    # Scan for analysis options
                    for filename in z.namelist():
                        if filename.endswith("0.json") or filename.endswith("1.json") or filename.endswith("2.json"):
                            try:
                                with z.open(filename) as f:
                                    data = json.load(f)
                                    # Look for ANOVA signature
                                    if "anova" in str(data.get("name", "")).lower() or "jmv::ANOVA" in str(data):
                                        omv_valid = True
                                        options = data.get("options", {})
                                        
                                        # Check Contrasts settings
                                        # Expected: contrasts=[{'var': 'spray', 'type': 'simple'}]
                                        contrasts = options.get("contrasts", [])
                                        for c in contrasts:
                                            if c.get("var") == "spray" and c.get("type") == "simple":
                                                contrast_set = True
                                                break
                            except:
                                continue
            
            if omv_valid:
                score += 15
                feedback_parts.append("Valid ANOVA analysis found in OMV")
            if contrast_set:
                score += 20
                feedback_parts.append("Simple contrasts configured")
                
        except Exception as e:
            feedback_parts.append(f"Error analyzing OMV: {str(e)}")
        finally:
            if os.path.exists(temp_omv.name):
                os.unlink(temp_omv.name)

    # 3. Verify Reported Value
    report_exists = result.get("report_exists", False)
    value_correct = False
    
    if report_exists:
        content = result.get("report_content", "").strip()
        try:
            # Clean content to find the number
            import re
            numbers = re.findall(r"-?\d+\.?\d*", content)
            if numbers:
                reported_val = float(numbers[0])
                if abs(reported_val - EXPECTED_T_VALUE) < TOLERANCE:
                    value_correct = True
                    score += 35
                    feedback_parts.append(f"Correct t-value reported ({reported_val})")
                else:
                    feedback_parts.append(f"Incorrect t-value reported ({reported_val}, expected {EXPECTED_T_VALUE})")
            else:
                feedback_parts.append("No number found in report")
        except:
            feedback_parts.append("Could not parse report content")

    # 4. Implicit check: if value is correct, they MUST have reordered the factor
    # If they didn't reorder (Ref=A), C vs A is:
    # Mean A=14.5, C=2.1, Diff=-12.4, t = -12.4/1.6 = -7.75
    # The expected -9.11 is distinct enough from -7.75.
    if value_correct:
        factor_reordered = True
        score += 20
        feedback_parts.append("Factor levels confirmed reordered (inferred from correct value)")
    elif contrast_set and not value_correct:
        # Partial credit if they set up contrasts but got wrong value (maybe didn't reorder)
        pass

    # 5. VLM Check for Trajectory (Process Verification)
    # Ensure they actually used the GUI
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        try:
            vlm_res = query_vlm(
                images=frames,
                prompt="Do these screenshots show a user configuring statistical software? Specifically, look for: 1. A 'Data' view where variable levels are reordered. 2. An 'ANOVA' analysis panel. 3. A 'Contrasts' option being selected."
            )
            if vlm_res.get("success"):
                score += 0  # Just logging for now, relying on programmatic checks primarily
        except:
            pass

    passed = score >= 80  # Strict pass: needs correct value + OMV existence
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }