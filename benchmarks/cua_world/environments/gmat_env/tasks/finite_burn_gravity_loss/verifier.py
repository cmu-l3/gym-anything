#!/usr/bin/env python3
"""
Verifier for finite_burn_gravity_loss@1

Agent must model a Hohmann transfer from 400km to 800km circular using
both Impulsive burns and Finite burns, then calculate the Delta-V penalty
(gravity loss).

Scoring logic (Total 100, pass >= 60):
- script_created: 5
- spacecraft_defined (initial SMA ~6771km): 5
- impulsive_burns_present: 10
- finite_burn_setup (Tank, Thruster, FiniteBurn): 15
- thruster_params_correct (Thrust=400N, Isp=316s): 10
- propagation_sequence (>2 propagations): 5
- report_written (fields exist): 5
- impulsive_dv_valid (190-250 m/s): 15
- finite_dv_valid (195-280 m/s): 10
- gravity_loss_positive (finite > impulsive): 10
- gravity_loss_range (1 to 35 m/s): 5
- final_orbit_reasonable (SMA ~ 7171km): 5

Pass condition: score >= 60 AND finite_burn_setup AND gravity_loss_positive
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_finite_burn_gravity_loss(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    sma_init_min = metadata.get('initial_sma_min_km', 6750.0)
    sma_init_max = metadata.get('initial_sma_max_km', 6790.0)
    sma_fin_min = metadata.get('final_sma_min_km', 7120.0)
    sma_fin_max = metadata.get('final_sma_max_km', 7220.0)
    imp_dv_min = metadata.get('impulsive_dv_min', 190.0)
    imp_dv_max = metadata.get('impulsive_dv_max', 250.0)
    fin_dv_min = metadata.get('finite_dv_min', 195.0)
    fin_dv_max = metadata.get('finite_dv_max', 280.0)
    gl_min = metadata.get('gravity_loss_min', 1.0)
    gl_max = metadata.get('gravity_loss_max', 35.0)

    # Load task_result.json
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

    score = 0
    feedback = []
    finite_burn_setup_ok = False
    gravity_loss_positive = False

    script_stats = task_result.get('script_file', {})
    report_stats = task_result.get('report_file', {})
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/gravity_loss_mission.script')
    report_path = task_result.get('report_path', '/home/ga/GMAT_output/gravity_loss_report.txt')

    # ==========================
    # 1. Script & Setup Analysis
    # ==========================
    if script_stats.get('created_during_task'):
        score += 5
        feedback.append("Script created successfully.")
    else:
        feedback.append("Script not created or not modified during task.")

    if script_stats.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Spacecraft check
            if re.search(r'Create\s+Spacecraft', script_content, re.I):
                sma_matches = re.findall(r'\.SMA\s*=\s*([0-9\.]+)', script_content)
                has_init_sma = False
                for val in sma_matches:
                    if sma_init_min <= float(val) <= sma_init_max:
                        has_init_sma = True
                        break
                if has_init_sma:
                    score += 5
                    feedback.append(f"Spacecraft initial SMA correctly defined near 6771 km.")
                else:
                    feedback.append("Spacecraft SMA not defined near 6771 km.")

            # Impulsive Burn check
            impulsive_burns = re.findall(r'Create\s+ImpulsiveBurn', script_content, re.I)
            if len(impulsive_burns) >= 2:
                score += 10
                feedback.append("At least two ImpulsiveBurn objects present.")
            elif len(impulsive_burns) == 1:
                score += 5
                feedback.append("Only one ImpulsiveBurn object found.")

            # Finite Burn setup check
            has_finite = bool(re.search(r'Create\s+FiniteBurn', script_content, re.I))
            has_thruster = bool(re.search(r'Create\s+(ChemicalThruster|Thruster)', script_content, re.I))
            has_tank = bool(re.search(r'Create\s+FuelTank', script_content, re.I))
            if has_finite and has_thruster and has_tank:
                score += 15
                finite_burn_setup_ok = True
                feedback.append("FiniteBurn, Thruster, and FuelTank objects correctly instantiated.")
            else:
                feedback.append("Missing one or more Finite Burn setup objects (Tank/Thruster/FiniteBurn).")

            # Thruster params check
            thrust_ok = bool(re.search(r'\.(C1|ThrustMagnitude)\s*=\s*400', script_content, re.I))
            isp_ok = bool(re.search(r'\.(Isp|C2)\s*=\s*316', script_content, re.I))
            if thrust_ok and isp_ok:
                score += 10
                feedback.append("Thruster properly configured with 400N thrust and 316s Isp.")
            elif thrust_ok or isp_ok:
                score += 5
                feedback.append("Thruster partially configured (Thrust or Isp correct).")

            # Propagation sequence
            propagations = re.findall(r'Propagate\s+', script_content, re.I)
            if len(propagations) >= 2:
                score += 5
                feedback.append(f"Found {len(propagations)} propagation segments.")

        except Exception as e:
            feedback.append(f"Failed to parse script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # ==========================
    # 2. Report Analysis
    # ==========================
    if report_stats.get('created_during_task'):
        score += 5
        feedback.append("Report file created successfully.")
    else:
        feedback.append("Report file missing or not modified.")

    if report_stats.get('exists'):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_report.name)
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()

            def extract_val(pattern):
                match = re.search(pattern, report_content, re.I)
                if match:
                    try:
                        return float(match.group(1))
                    except ValueError:
                        pass
                return None

            impulsive_dv = extract_val(r'impulsive_total_dv_m_s:\s*([0-9\.]+)')
            finite_dv = extract_val(r'finite_total_dv_m_s:\s*([0-9\.]+)')
            gravity_loss = extract_val(r'gravity_loss_m_s:\s*([0-9\.]+)')
            fin_sma = extract_val(r'finite_final_sma_km:\s*([0-9\.]+)')

            if impulsive_dv is not None:
                if imp_dv_min <= impulsive_dv <= imp_dv_max:
                    score += 15
                    feedback.append(f"Impulsive total DV ({impulsive_dv} m/s) in expected range.")
                else:
                    feedback.append(f"Impulsive total DV ({impulsive_dv} m/s) out of expected range.")

            if finite_dv is not None:
                if fin_dv_min <= finite_dv <= fin_dv_max:
                    score += 10
                    feedback.append(f"Finite total DV ({finite_dv} m/s) in expected range.")
                else:
                    feedback.append(f"Finite total DV ({finite_dv} m/s) out of expected range.")

            if impulsive_dv is not None and finite_dv is not None:
                if finite_dv > impulsive_dv:
                    score += 10
                    gravity_loss_positive = True
                    feedback.append("Gravity loss is positive (Finite DV > Impulsive DV).")
                else:
                    feedback.append("Gravity loss is NOT positive. Finite burn should be less efficient.")

            if gravity_loss is not None:
                if gl_min <= gravity_loss <= gl_max:
                    score += 5
                    feedback.append(f"Calculated gravity loss ({gravity_loss} m/s) matches realistic expectations.")
                else:
                    feedback.append(f"Calculated gravity loss ({gravity_loss} m/s) is physically unusual.")

            if fin_sma is not None:
                if sma_fin_min <= fin_sma <= sma_fin_max:
                    score += 5
                    feedback.append(f"Final SMA ({fin_sma} km) is near the 800 km target altitude.")
                else:
                    feedback.append(f"Final SMA ({fin_sma} km) did not hit target altitude.")

        except Exception as e:
            feedback.append(f"Failed to parse report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

    # Determine final pass status
    key_criteria_met = finite_burn_setup_ok and gravity_loss_positive
    passed = (score >= 60) and key_criteria_met

    if passed:
        feedback.insert(0, f"SUCCESS: Passed with score {score}/100.")
    else:
        feedback.insert(0, f"FAILED: Score {score}/100. Key criteria met: Setup={finite_burn_setup_ok}, PositiveLoss={gravity_loss_positive}")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }