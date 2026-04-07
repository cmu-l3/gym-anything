#!/usr/bin/env python3
"""
Verifier for empirical_telemetry_conversion_derivation task.

Verification Criteria (100 pts, pass threshold 65):
1. Output file exists and was created during session (15 pts)
2. JSON Schema matches required format (15 pts)
3. Mathematical accuracy: Agent's reported m and b algebraically match their provided data points (20 pts)
4. System Restoration: TEMP1/TEMP2 are fluctuating (normalized) and TEMP3 == 85.0 (15 pts)
5. VLM Trajectory: Confirms agent actively used COSMOS Script Runner / APIs to override telemetry (35 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are auditing screenshots from an agent interacting with OpenC3 COSMOS satellite ground system.
The agent was tasked with empirically deriving telemetry conversion formulas by actively overriding telemetry values and observing the results.

Look at the progression of screenshots and identify if the agent performed the active workflow:
1. Did the agent open the 'Script Runner', 'Command Sender', or use a programmatic API tool?
2. Is there evidence of the agent executing commands related to `override_tlm`, `set_tlm`, or `normalize_tlm`?
3. Is there evidence of the agent querying or viewing RAW vs CONVERTED telemetry data?

Answer purely based on the visual evidence.
Respond strictly in JSON:
{
  "used_script_runner_or_api": true/false,
  "telemetry_tools_visible": true/false,
  "active_system_interaction": true/false,
  "confidence": "low/medium/high"
}"""

def verify_empirical_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/ivv_export_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/ivv_conversion_report.json')

    score = 0
    feedback = []

    # 1. Read export metadata
    export_meta = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            export_meta = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f"Missing export metadata: {e}"}
    finally:
        if os.path.exists(tmp_name): os.unlink(tmp_name)

    # Criterion 1: File Exists & Fresh (15 pts)
    file_exists = export_meta.get('file_exists', 'false') == 'true'
    file_is_new = export_meta.get('file_is_new', 'false') == 'true'

    if not file_exists:
        feedback.append("Report file not found on Desktop.")
    elif not file_is_new:
        feedback.append("Report file predates task start (no content credit).")
    else:
        score += 15
        feedback.append("Report file created during session (+15).")

    # 2. Parse Agent's Report
    report = None
    if file_exists and file_is_new:
        try:
            with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
                tmp_name = tmp.name
            copy_from_env(output_file, tmp_name)
            with open(tmp_name, 'r') as f:
                report = json.load(f)
        except Exception as e:
            feedback.append(f"Report JSON parse failed: {e}")
        finally:
            if os.path.exists(tmp_name): os.unlink(tmp_name)

    # Criterion 2: Schema (15 pts) & Criterion 3: Mathematical Accuracy (20 pts)
    if report:
        derivation = report.get('derivation', {})
        if "TEMP1" in derivation and "TEMP2" in derivation:
            score += 15
            feedback.append("JSON schema matches required structure (+15).")

            math_points = 0
            for sensor in ["TEMP1", "TEMP2"]:
                data = derivation.get(sensor, {})
                pts = data.get('data_points', [])
                coef = data.get('coefficients', {})
                if len(pts) >= 2 and 'm' in coef and 'b' in coef:
                    try:
                        x1, y1 = float(pts[0].get('raw', 0)), float(pts[0].get('converted', 0))
                        x2, y2 = float(pts[1].get('raw', 0)), float(pts[1].get('converted', 0))
                        m_rep, b_rep = float(coef['m']), float(coef['b'])

                        if abs(x2 - x1) > 1e-6:
                            m_calc = (y2 - y1) / (x2 - x1)
                            b_calc = y1 - (m_calc * x1)
                            if abs(m_calc - m_rep) < 0.05 and abs(b_calc - b_rep) < 0.05:
                                math_points += 10
                                feedback.append(f"{sensor} math derivation verified (+10).")
                            else:
                                feedback.append(f"{sensor} derivation math error (calc: m={m_calc:.3f}, b={b_calc:.3f} | rep: m={m_rep}, b={b_rep}).")
                        else:
                            feedback.append(f"{sensor} test points identical, cannot calculate slope.")
                    except ValueError:
                        feedback.append(f"Invalid numeric values in {sensor} data.")
            score += math_points
        else:
            feedback.append("Missing TEMP1 or TEMP2 in derivation schema.")

    # Criterion 4: System Restoration (15 pts)
    tlm = export_meta.get('telemetry_samples', {})
    try:
        t1a, t1b = float(tlm.get('t1_a', 0)), float(tlm.get('t1_b', 0))
        t2a, t2b = float(tlm.get('t2_a', 0)), float(tlm.get('t2_b', 0))
        t3a, t3b = float(tlm.get('t3_a', 0)), float(tlm.get('t3_b', 0))

        t1_norm = abs(t1a - t1b) > 0.01  # True if fluctuating
        t2_norm = abs(t2a - t2b) > 0.01
        t3_locked = (abs(t3a - 85.0) < 0.1) and (abs(t3b - 85.0) < 0.1)

        rest_score = 0
        if t1_norm and t2_norm:
            rest_score += 7
            feedback.append("TEMP1/TEMP2 normalized successfully (+7).")
        else:
            feedback.append("TEMP1/TEMP2 not properly normalized.")

        if t3_locked:
            rest_score += 8
            feedback.append("TEMP3 verified locked at 85.0 (+8).")
        else:
            feedback.append(f"TEMP3 not locked at 85.0 (Actual: {t3b}).")

        score += rest_score
    except Exception as e:
        feedback.append(f"System telemetry check failed: {e}")

    # Criterion 5: VLM Trajectory Verification (35 pts)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
                if vlm_res and vlm_res.get('success'):
                    v_data = vlm_res.get('parsed', {})
                    if v_data.get('used_script_runner_or_api') and v_data.get('active_system_interaction'):
                        vlm_score += 35
                        feedback.append("VLM confirmed active COSMOS API/Script usage (+35).")
                    else:
                        feedback.append("VLM did not observe active API/Script Runner usage.")
                else:
                    feedback.append("VLM query format failed.")
            else:
                feedback.append("No trajectory frames available for VLM.")
        except ImportError:
            feedback.append("VLM utilities not available.")
    else:
        feedback.append("query_vlm not provided in env_info.")

    score += vlm_score

    # Compute Pass/Fail
    passed = score >= 65 and file_exists and file_is_new
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }