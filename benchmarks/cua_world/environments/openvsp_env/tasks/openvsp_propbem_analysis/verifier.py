#!/usr/bin/env python3
"""
Verifier for openvsp_propbem_analysis task.

Checks:
  1. Geometry: 3blade_prop.vsp3 saved and NumBlades changed to 3 (25 pts)
  2. Execution: PropBEM CSV generated with exactly 15 data rows (30 pts)
  3. Visual trajectory: VLM confirms use of PropBEM dialog (15 pts)
  4. Reporting: prop_report.txt contains correct peak efficiency & optimal J (30 pts)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_propbem_csv(csv_content: str):
    """Parses PropBEM CSV to extract data rows and identify J and Eta columns."""
    data_rows = []
    eta_col = None
    j_col = None

    lines = [line.strip() for line in csv_content.splitlines() if line.strip()]
    for line in lines:
        if line.startswith('#'):
            header_str = line.lstrip('#').strip().lower()
            if 'eta' in header_str or 'eff' in header_str or 'j' in header_str:
                headers = [h.strip() for h in header_str.split(',')]
                for i, h in enumerate(headers):
                    if 'eta' in h or 'eff' in h: eta_col = i
                    if 'j' in h or 'adv' in h: j_col = i
        else:
            try:
                vals = [float(x) for x in line.split(',')]
                if len(vals) > 2:
                    data_rows.append(vals)
            except ValueError:
                pass

    # Fallback column mapping for standard PropBEM format: J, CT, CP, CQ, Eta
    if data_rows and (eta_col is None or j_col is None):
        if len(data_rows[0]) >= 5:
            j_col = 0
            eta_col = 4

    return data_rows, j_col, eta_col

def extract_numbers(text: str):
    """Extracts all standalone floating point numbers from text."""
    # Match numbers like 0.82, 1.5, .75
    return [float(m) for m in re.findall(r'\b\d+\.\d+\b|\b\.\d+\b|\b\d+\b', text)]

def verify_openvsp_propbem_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve exported result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/openvsp_propbem_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- 1. Verify Geometry Modification (25 pts) ---
    if data.get('model_saved'):
        model_xml = data.get('model_content', '')
        # Robustly find NumBlades value in XML
        match = re.search(r'NumBlades.*?Value=["\']([0-9.]+)["\']', model_xml, re.IGNORECASE)
        if not match:
            match = re.search(r'Value=["\']([0-9.]+)["\'].*?Name=["\']NumBlades["\']', model_xml, re.IGNORECASE)
        
        if match:
            blades = float(match.group(1))
            if abs(blades - 3.0) < 0.1:
                score += 25
                feedback.append("✅ 3-blade geometry saved correctly.")
            else:
                feedback.append(f"❌ Model saved but NumBlades is {blades}, expected 3.0.")
        else:
            feedback.append("❌ Model saved but could not parse NumBlades value.")
    else:
        feedback.append("❌ Modified model was not saved to the expected location.")

    # --- 2. Verify PropBEM Execution (30 pts) ---
    csv_exists = data.get('csv_exists') and data.get('csv_created_during_task')
    csv_rows, j_col, eta_col = parse_propbem_csv(data.get('csv_content', ''))
    
    true_max_eta = None
    true_opt_j = None

    if csv_exists:
        num_points = len(csv_rows)
        if num_points >= 14 and num_points <= 16:  # Tolerant to 1 off
            score += 30
            feedback.append(f"✅ PropBEM executed with {num_points} points.")
        elif num_points > 0:
            score += 15
            feedback.append(f"⚠️ PropBEM executed but with {num_points} points (expected 15).")
        else:
            feedback.append("❌ PropBEM CSV generated but contained no data rows.")
        
        # Determine ground truth from agent's own CSV run
        if csv_rows and j_col is not None and eta_col is not None:
            try:
                max_row = max(csv_rows, key=lambda x: x[eta_col])
                true_max_eta = max_row[eta_col]
                true_opt_j = max_row[j_col]
            except IndexError:
                pass
    else:
        feedback.append("❌ PropBEM analysis CSV not found or not generated during task.")

    # --- 3. VLM Verification of UI Interaction (15 pts) ---
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4) + [get_final_screenshot(traj)]
            vlm_prompt = (
                "Review these trajectory frames for an OpenVSP session. "
                "Did the user open the 'Propeller BEM' analysis dialog window (usually found under the Analysis menu)? "
                "Respond in JSON: {\"opened_propbem_dialog\": true/false}"
            )
            vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
            
            if vlm_result.get('success') and vlm_result.get('parsed', {}).get('opened_propbem_dialog'):
                score += 15
                feedback.append("✅ VLM confirmed PropBEM analysis dialog interaction.")
            else:
                feedback.append("❌ VLM did not clearly detect PropBEM dialog interaction.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            # Fallback point grant if CSV was successfully generated with exact points
            if csv_exists and len(csv_rows) == 15:
                score += 15
                feedback.append("✅ VLM fallback: Exact CSV parameters imply dialog use.")

    # --- 4. Verify Report (30 pts) ---
    if data.get('report_exists'):
        report_text = data.get('report_content', '')
        reported_nums = extract_numbers(report_text)
        
        # Verify Max Efficiency (15 pts)
        if true_max_eta is not None:
            if any(abs(n - true_max_eta) <= 0.02 for n in reported_nums):
                score += 15
                feedback.append(f"✅ Report correctly identified max efficiency (~{true_max_eta:.2f}).")
            else:
                feedback.append(f"❌ Report failed to state the max efficiency (expected ~{true_max_eta:.2f}).")
        
        # Verify Optimal J (15 pts)
        if true_opt_j is not None:
            if any(abs(n - true_opt_j) <= 0.05 for n in reported_nums):
                score += 15
                feedback.append(f"✅ Report correctly identified optimal J (~{true_opt_j:.2f}).")
            else:
                feedback.append(f"❌ Report failed to state the optimal J (expected ~{true_opt_j:.2f}).")
                
        if true_max_eta is None:
            feedback.append("⚠️ Could not verify report numbers because CSV data was invalid/missing.")
    else:
        feedback.append("❌ Summary report not created.")

    # Determine pass/fail
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }