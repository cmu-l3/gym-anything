#!/usr/bin/env python3
"""
Verifier for openvsp_wind_tunnel_model_prep task.

Scoring Criteria (100 points total):
1. VSP3 model saved and modified during task (10 pts)
2. Global Scaling Applied (Wing TotalSpan is ~0.58m instead of ~58m) (25 pts)
3. Sting Component Created (Pod named 'Sting') (15 pts)
4. Sting Dimensions Correct (Length ~ 0.3, Fineness ~ 15.0) (20 pts)
5. Sting Position Correct (X Location ~ 0.60) (15 pts)
6. STL Exported successfully (15 pts)

Also uses VLM on trajectory frames to verify GUI interaction.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wind_tunnel_model_prep(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected metadata
    metadata = task_info.get('metadata', {})
    
    # 1. Load exported data from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    task_start = result.get('task_start', 0)

    # --- Criterion 1: VSP3 File Saved (10 pts) ---
    vsp3_exists = result.get('vsp3_exists', False)
    vsp3_mtime = result.get('vsp3_mtime', 0)
    
    if not vsp3_exists:
        feedback.append("❌ wt_model.vsp3 not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
    
    if vsp3_mtime >= task_start:
        score += 10
        feedback.append("✅ wt_model.vsp3 saved")
    else:
        feedback.append("❌ wt_model.vsp3 is stale (created before task)")

    content = result.get('vsp3_content', "")

    # --- Criterion 2: Global Scaling (25 pts) ---
    # The original eCRM-001 wing has a span of ~58.7 meters.
    # At 0.01 scale, maximum TotalSpan in the file should be between 0.4 and 0.8 meters.
    span_matches = re.findall(r'<TotalSpan\s+Value="([^"]+)"', content)
    spans = [float(s) for s in span_matches] if span_matches else []
    
    scaled_correctly = False
    if spans:
        max_span = max(spans)
        if 0.40 <= max_span <= 0.80:
            score += 25
            scaled_correctly = True
            feedback.append(f"✅ Global scaling applied (Max Span={max_span:.3f}m)")
        elif max_span > 10.0:
            feedback.append(f"❌ Model not scaled (Max Span={max_span:.1f}m)")
        else:
            feedback.append(f"❌ Model scaled incorrectly (Max Span={max_span:.3f}m)")
    else:
        feedback.append("❌ Wing span parameters not found")

    # --- Criterion 3: Sting Component Exists (15 pts) ---
    # Look for a Geom block that has <Name>Sting</Name> (case-insensitive)
    sting_match = re.search(r'(?i)<Geom[^>]*>.*?<Name>Sting</Name>.*?</Geom>', content, re.DOTALL)
    
    sting_exists = False
    sting_xml = ""
    if sting_match:
        sting_exists = True
        sting_xml = sting_match.group(0)
        score += 15
        feedback.append("✅ Sting component created")
    else:
        feedback.append("❌ Sting component not found")

    # --- Criterion 4 & 5: Sting Dimensions and Location (35 pts) ---
    if sting_exists:
        # Length ~ 0.3 (accept 0.25 to 0.35)
        # Note: OpenVSP Pod length is usually DesignLength or Length
        len_m = re.search(r'<(?:Design)?Length\s+Value="([^"]+)"', sting_xml)
        fine_m = re.search(r'<Fineness\s+Value="([^"]+)"', sting_xml)
        xloc_m = re.search(r'<X_Rel_Location\s+Value="([^"]+)"', sting_xml)

        if len_m and fine_m:
            l_val = float(len_m.group(1))
            f_val = float(fine_m.group(1))
            
            dim_score = 0
            if 0.25 <= l_val <= 0.35: dim_score += 10
            if 14.0 <= f_val <= 16.0: dim_score += 10
            
            score += dim_score
            if dim_score == 20:
                feedback.append(f"✅ Sting dimensions correct (L={l_val:.2f}, F={f_val:.1f})")
            else:
                feedback.append(f"⚠️ Sting dimensions imprecise (L={l_val:.2f}, F={f_val:.1f})")
        else:
            feedback.append("❌ Sting Length/Fineness parameters missing")

        if xloc_m:
            x_val = float(xloc_m.group(1))
            if 0.50 <= x_val <= 0.70:
                score += 15
                feedback.append(f"✅ Sting positioned correctly (X={x_val:.2f})")
            else:
                feedback.append(f"❌ Sting positioned incorrectly (X={x_val:.2f})")
        else:
            feedback.append("❌ Sting X_Rel_Location missing")

    # --- Criterion 6: STL Exported (15 pts) ---
    stl_exists = result.get('stl_exists', False)
    stl_mtime = result.get('stl_mtime', 0)
    stl_size = result.get('stl_size', 0)
    
    if stl_exists and stl_size > 500 and stl_mtime >= task_start:
        score += 15
        feedback.append(f"✅ STL exported ({stl_size} bytes)")
    elif stl_exists:
        feedback.append(f"❌ STL exported but invalid/stale ({stl_size} bytes)")
    else:
        feedback.append("❌ wt_model.stl not found")

    # --- VLM Trajectory Verification ---
    # Ensure the agent actually interacted with the GUI
    vlm_verified = False
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = "Does this sequence of images show a user interacting with OpenVSP (an aircraft CAD tool) to scale a model and add a cylindrical sting mount to the rear?"
                vlm_resp = query_vlm(images=images, prompt=prompt)
                
                # Check for positive affirmative in VLM response
                if vlm_resp and vlm_resp.get("success"):
                    ans = vlm_resp.get("answer", "").lower()
                    if "yes" in ans[:10]:
                        vlm_verified = True
                        feedback.append("✅ VLM verified GUI interaction")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            # Do not penalize if VLM infrastructure fails

    # Calculate final pass/fail
    # Must have scaled the model, created the sting, and exported an STL to pass
    key_criteria_met = scaled_correctly and sting_exists and stl_exists
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }