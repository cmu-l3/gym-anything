#!/usr/bin/env python3
"""
Verifier for openvsp_parasite_drag_buildup task.

Verifies:
1. Export CSV exists and was created during the task (20 pts)
2. Report file exists and was created during the task (10 pts)
3. Report contains a realistic Total CD0 (20 pts)
4. Report lists at least 3 distinct component breakdowns (15 pts)
5. Report identifies the top drag contributor (15 pts)
6. VLM trajectory verifies the agent used the Parasite Drag tool (20 pts)

Pass threshold: 60.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_openvsp_parasite_drag_buildup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    cd0_min = metadata.get('cd0_min', 0.008)
    cd0_max = metadata.get('cd0_max', 0.050)
    expected_components = metadata.get('expected_components', ['wing', 'fuse', 'body', 'tail', 'horiz', 'vert'])
    
    # 1. Retrieve the result JSON
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/openvsp_parasite_drag_result.json", local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve export results: {e}"
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []
    task_start = data.get('task_start_timestamp', 0)
    
    csv_info = data.get('csv', {})
    report_info = data.get('report', {})

    # -------------------------------------------------------------------------
    # Criterion 1 & 2: Output files exist and are fresh (Anti-Gaming)
    # -------------------------------------------------------------------------
    csv_valid = False
    if csv_info.get('exists', False):
        if csv_info.get('mtime', 0) >= task_start:
            if csv_info.get('size', 0) > 50:
                score += 20
                csv_valid = True
                feedback_parts.append("✅ CSV export found and valid (+20)")
            else:
                feedback_parts.append("❌ CSV export is suspiciously small (+0)")
        else:
            feedback_parts.append("❌ CSV export predates task start (stale file) (+0)")
    else:
        feedback_parts.append("❌ CSV export not found (+0)")

    report_valid = False
    if report_info.get('exists', False):
        if report_info.get('mtime', 0) >= task_start:
            if report_info.get('size', 0) > 50:
                score += 10
                report_valid = True
                feedback_parts.append("✅ Report file found (+10)")
            else:
                feedback_parts.append("❌ Report file is suspiciously small (+0)")
        else:
            feedback_parts.append("❌ Report file predates task start (stale file) (+0)")
    else:
        feedback_parts.append("❌ Report file not found (+0)")

    # -------------------------------------------------------------------------
    # Criterion 3, 4 & 5: Report Content Parsing
    # -------------------------------------------------------------------------
    report_content = report_info.get('content', '')
    if report_valid:
        # 3. Extract Total CD0
        cd0_match = re.search(r'(?i)(?:total\s*cd0|cd0\s*total|total\s*drag|cd0)\s*[:=]?\s*([0-9]*\.[0-9]+)', report_content)
        if cd0_match:
            try:
                cd0_val = float(cd0_match.group(1))
                if cd0_min <= cd0_val <= cd0_max:
                    score += 20
                    feedback_parts.append(f"✅ Plausible Total CD0 extracted: {cd0_val} (+20)")
                else:
                    feedback_parts.append(f"❌ Extracted CD0 ({cd0_val}) is outside plausible bounds [{cd0_min}, {cd0_max}] (+0)")
            except ValueError:
                feedback_parts.append("❌ Found CD0 text but could not parse float (+0)")
        else:
            # Fallback: find any number in range
            nums = re.findall(r'[0-9]*\.[0-9]+', report_content)
            found_cd0 = False
            for n in nums:
                if cd0_min <= float(n) <= cd0_max:
                    score += 15
                    feedback_parts.append(f"⚠️ CD0 partially matched (unlabeled but in range): {n} (+15)")
                    found_cd0 = True
                    break
            if not found_cd0:
                feedback_parts.append("❌ No valid CD0 value found in report (+0)")

        # 4. Extract Component Breakdown
        # Count lines that seem to have a component keyword and a decimal number
        comp_count = 0
        lines = report_content.splitlines()
        for line in lines:
            line_lower = line.lower()
            if any(c in line_lower for c in expected_components):
                if re.search(r'[0-9]*\.[0-9]+', line):
                    comp_count += 1
        
        if comp_count >= 3:
            score += 15
            feedback_parts.append(f"✅ Component breakdown found ({comp_count} components) (+15)")
        elif comp_count > 0:
            score += 5
            feedback_parts.append(f"⚠️ Partial component breakdown found ({comp_count} components) (+5)")
        else:
            feedback_parts.append("❌ Component breakdown not found in report (+0)")

        # 5. Top Drag Contributor explicitly identified
        top_match = re.search(r'(?i)(?:top|largest|maximum|biggest)\s*(?:drag)?\s*(?:contributor|source|component)\s*[:=]?\s*([a-zA-Z_]+)', report_content)
        if top_match:
            top_comp = top_match.group(1).lower()
            # Often it's the Wing or Fuselage
            if len(top_comp) > 2:
                score += 15
                feedback_parts.append(f"✅ Top contributor identified: {top_comp} (+15)")
            else:
                feedback_parts.append("❌ Top contributor identified but name too short/invalid (+0)")
        else:
            feedback_parts.append("❌ Top drag contributor not explicitly identified (+0)")

    # -------------------------------------------------------------------------
    # Criterion 6: VLM Trajectory Analysis (20 pts)
    # -------------------------------------------------------------------------
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            prompt = """You are evaluating an agent performing a task in OpenVSP.
Task: Run Parasite Drag analysis at Mach 0.78, Altitude 35000 ft, turbulent flow.
Look at these screenshots across the trajectory and determine:
1. Did the agent open the 'Parasite Drag' analysis tool? (Look for a window titled Parasite Drag)
2. Did the agent configure the flight conditions to roughly Mach 0.78 and Alt 35000?
3. Did the agent execute the computation? (Look for tabular results appearing in the window)

Respond with a JSON object containing boolean values:
{
    "opened_parasite_drag": true/false,
    "configured_conditions": true/false,
    "computed_results": true/false
}
"""
            vlm_res = query_vlm(images=frames + [final] if final else frames, prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                vlm_score = 0
                if parsed.get("opened_parasite_drag"): vlm_score += 10
                if parsed.get("configured_conditions"): vlm_score += 5
                if parsed.get("computed_results"): vlm_score += 5
                
                score += vlm_score
                feedback_parts.append(f"VLM Verification (+{vlm_score})")
            else:
                feedback_parts.append("⚠️ VLM verification failed to parse (+0)")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append("⚠️ VLM verification error (+0)")
    else:
        feedback_parts.append("⚠️ VLM not configured (+0)")

    passed = score >= 60 and csv_valid and report_valid
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }