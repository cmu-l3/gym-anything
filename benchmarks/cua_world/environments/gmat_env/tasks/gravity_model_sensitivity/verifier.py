#!/usr/bin/env python3
"""
Verifier for gravity_model_sensitivity@1

Agent must simulate a 7-day orbit under 4 different gravity truncation levels,
without confounding forces (drag, SRP, third-body), and compute position divergence.

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script created during task window
  - four_spacecraft (10): 4 distinct spacecraft definitions
  - four_force_models (15): 4 distinct force models defined
  - gravity_orders_correct (10): Degree/Order sets contain {2, 4, 12, >=50}
  - no_confounding_forces (5): No drag, SRP, or point masses
  - four_propagators (5): 4 distinct propagators
  - propagation_7days (5): ElapsedDays = 7 stopping condition
  - gmat_reports_generated (10): ≥1 output report file exists
  - analysis_report_written (10): Result text file exists
  - divergence_ordering_correct (15): J2 > 4x4 > 12x12
  - divergence_magnitudes_valid (5): Divergences in physically plausible bounds

Pass condition: score >= 60 AND divergence_ordering_correct AND four_force_models
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_gravity_model_sensitivity(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    scores = {
        "script_created": 10,
        "four_spacecraft": 10,
        "four_force_models": 15,
        "gravity_orders_correct": 10,
        "no_confounding_forces": 5,
        "four_propagators": 5,
        "propagation_7days": 5,
        "gmat_reports_generated": 10,
        "analysis_report_written": 10,
        "divergence_ordering_correct": 15,
        "divergence_magnitudes_valid": 5,
    }

    total_score = 0
    feedback = []
    ordering_ok = False
    four_fm_ok = False

    # Load task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Script created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Analyze script content
    script_path = task_result.get('script_path', '/home/ga/Documents/missions/gravity_study.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Count Spacecraft
            sc_count = len(re.findall(r'Create\s+Spacecraft', script_content))
            if sc_count >= 4:
                total_score += scores["four_spacecraft"]
                feedback.append(f"4+ spacecraft defined ({sc_count} found).")
            elif sc_count > 0:
                total_score += int(scores["four_spacecraft"] * (sc_count / 4.0))
                feedback.append(f"Only {sc_count} spacecraft defined.")
            
            # Count ForceModels
            fm_count = len(re.findall(r'Create\s+ForceModel', script_content))
            if fm_count >= 4:
                total_score += scores["four_force_models"]
                four_fm_ok = True
                feedback.append(f"4+ force models defined ({fm_count} found).")
            elif fm_count > 0:
                total_score += int(scores["four_force_models"] * (fm_count / 4.0))
                feedback.append(f"Only {fm_count} force models defined.")

            # Check Gravity Orders
            degrees = [int(d) for d in re.findall(r'\.Degree\s*=\s*(\d+)', script_content)]
            if 2 in degrees and 4 in degrees and 12 in degrees and any(d >= 50 for d in degrees):
                total_score += scores["gravity_orders_correct"]
                feedback.append("Required gravity degrees (2, 4, 12, 70) found in script.")
            else:
                feedback.append(f"Missing required gravity degrees. Found: {set(degrees)}")

            # Check for confounding forces
            has_drag = bool(re.search(r'\.Drag\.AtmosphereModel', script_content))
            has_srp = bool(re.search(r'\.SRP\s*=\s*On', script_content))
            has_points = bool(re.search(r'\.PointMasses\s*=\s*\{[^\}]+\}', script_content))
            if not has_drag and not has_srp and not has_points:
                total_score += scores["no_confounding_forces"]
                feedback.append("No confounding forces found (Gravity isolated).")
            else:
                feedback.append("Confounding forces (Drag, SRP, or PointMasses) detected.")

            # Count Propagators
            prop_count = len(re.findall(r'Create\s+Propagator', script_content))
            if prop_count >= 4:
                total_score += scores["four_propagators"]
                feedback.append(f"4+ propagators defined ({prop_count} found).")
            elif prop_count > 0:
                total_score += int(scores["four_propagators"] * (prop_count / 4.0))

            # Check Propagation duration (ElapsedDays = 7)
            if bool(re.search(r'\.ElapsedDays\s*=\s*7\b', script_content)):
                total_score += scores["propagation_7days"]
                feedback.append("Propagation for 7 days found.")

        except Exception as e:
            feedback.append(f"Error parsing script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. GMAT Reports Generated
    reports_count = task_result.get('gmat_reports_generated', 0)
    if reports_count > 0:
        total_score += scores["gmat_reports_generated"]
        feedback.append(f"GMAT generated {reports_count} report files.")

    # 4. Analysis Report Check
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('exists') and report_file.get('created_during_task'):
        total_score += scores["analysis_report_written"]
        feedback.append("Analysis report written.")

        try:
            j2_val = float(task_result.get('j2_divergence', 0))
        except (ValueError, TypeError):
            j2_val = 0.0
            
        try:
            f4_val = float(task_result.get('f4x4_divergence', 0))
        except (ValueError, TypeError):
            f4_val = 0.0
            
        try:
            f12_val = float(task_result.get('f12x12_divergence', 0))
        except (ValueError, TypeError):
            f12_val = 0.0

        if j2_val > 0 and f4_val > 0 and f12_val > 0:
            if j2_val > f4_val > f12_val:
                total_score += scores["divergence_ordering_correct"]
                ordering_ok = True
                feedback.append(f"Physically correct ordering: J2 ({j2_val:.2f}) > 4x4 ({f4_val:.2f}) > 12x12 ({f12_val:.4f}).")
            else:
                feedback.append(f"Incorrect physical ordering: J2={j2_val}, 4x4={f4_val}, 12x12={f12_val}.")
            
            # Check magnitudes
            if (0.1 < j2_val < 500.0) and (0.01 < f4_val < 100.0) and (0.0001 < f12_val < 10.0):
                total_score += scores["divergence_magnitudes_valid"]
                feedback.append("Divergence magnitudes are in physically expected bounds.")
            else:
                feedback.append("Divergence magnitudes are outside expected bounds.")
        else:
            feedback.append("Could not extract non-zero divergences from the report.")
    else:
        feedback.append("Analysis report not found or not modified.")

    # Final Evaluation
    passed = total_score >= 60 and ordering_ok and four_fm_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "score": total_score,
            "ordering_ok": ordering_ok,
            "four_fm_ok": four_fm_ok
        }
    }