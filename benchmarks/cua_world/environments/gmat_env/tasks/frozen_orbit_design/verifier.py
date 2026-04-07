#!/usr/bin/env python3
"""
Verifier for frozen_orbit_design@1

Agent must compute the J2/J3 frozen eccentricity, design a GMAT script with two
spacecraft (frozen vs reference non-frozen), propagate for 60 days using a full
force model (Gravity 10x10+, Drag, SRP), and report stability metrics.

Scoring (total 100 pts, pass >= 60):
  - script_created (5)
  - two_spacecraft (10)
  - frozen_ecc_correct (20)
  - frozen_aop_correct (10)
  - gravity_model_adequate (10)
  - drag_and_srp (5)
  - propagation_60days (5)
  - report_written (5)
  - frozen_ecc_stable (15)
  - frozen_alt_stable (5)
  - reference_less_stable (5)
  - stability_ratio_valid (5)

Pass condition: score >= 60 AND frozen_ecc_correct AND frozen_aop_correct
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_gmat_script(content):
    """Parse GMAT script properties into a dictionary of objects and their properties."""
    sc_data = {}
    
    # Clean out comments
    content = re.sub(r'%.*$', '', content, flags=re.MULTILINE)
    
    # Match GMAT lines: GMAT <ObjName>.<Property> = <Value>;
    # Using a robust regex to handle complex values like arrays or strings
    props = re.findall(r'GMAT\s+([a-zA-Z0-9_]+)\.([a-zA-Z0-9_\.]+)\s*=\s*([^;]+);', content)
    
    for obj, prop, val in props:
        obj = obj.strip()
        prop = prop.strip()
        val = val.strip().strip("'").strip('"')
        if obj not in sc_data:
            sc_data[obj] = {}
        sc_data[obj][prop] = val
        
    return sc_data

def verify_frozen_orbit_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    frozen_ecc_min = metadata.get('frozen_ecc_min', 0.0005)
    frozen_ecc_max = metadata.get('frozen_ecc_max', 0.002)
    aop_1 = metadata.get('frozen_aop_1', 90.0)
    aop_2 = metadata.get('frozen_aop_2', 270.0)
    aop_tol = metadata.get('aop_tolerance', 10.0)
    grav_deg_min = metadata.get('gravity_degree_min', 10)
    prop_days_min = metadata.get('prop_days_min', 55.0)
    
    ecc_var_max = metadata.get('frozen_ecc_var_max', 0.0005)
    alt_range_max = metadata.get('frozen_alt_range_max', 10.0)
    stab_ratio_min = metadata.get('stability_ratio_min', 2.0)

    scores = {
        "script_created": 5,
        "two_spacecraft": 10,
        "frozen_ecc_correct": 20,
        "frozen_aop_correct": 10,
        "gravity_model_adequate": 10,
        "drag_and_srp": 5,
        "propagation_60days": 5,
        "report_written": 5,
        "frozen_ecc_stable": 15,
        "frozen_alt_stable": 5,
        "reference_less_stable": 5,
        "stability_ratio_valid": 5,
    }

    total_score = 0
    feedback = []
    
    frozen_ecc_ok = False
    frozen_aop_ok = False

    # Load task result JSON
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

    # 1. Check script
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # Parse script
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/frozen_orbit_script.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()
            
            sc_data = parse_gmat_script(script_content)
            
            # Identify spacecraft (objects with ECC and AOP)
            spacecraft = {k: v for k, v in sc_data.items() if 'ECC' in v and 'AOP' in v}
            
            # 2. Check for two spacecraft
            if len(spacecraft) >= 2:
                total_score += scores["two_spacecraft"]
                feedback.append(f"Found {len(spacecraft)} spacecraft definitions.")
            else:
                feedback.append(f"Found {len(spacecraft)} spacecraft definition(s), expected at least 2.")
            
            # Find the "frozen" one (the one with AOP near 90 or 270)
            frozen_sc = None
            for name, props in spacecraft.items():
                try:
                    aop = float(props['AOP'])
                    if abs(aop - aop_1) <= aop_tol or abs(aop - aop_2) <= aop_tol:
                        frozen_sc = props
                        break
                except ValueError:
                    pass
                    
            if not frozen_sc and len(spacecraft) > 0:
                # Fallback to the first one if we can't cleanly identify
                frozen_sc = list(spacecraft.values())[0]

            # 3 & 4. Check Frozen ECC and AOP
            if frozen_sc:
                try:
                    ecc = float(frozen_sc['ECC'])
                    if frozen_ecc_min <= ecc <= frozen_ecc_max:
                        total_score += scores["frozen_ecc_correct"]
                        frozen_ecc_ok = True
                        feedback.append(f"Frozen ECC is correct: {ecc}")
                    else:
                        feedback.append(f"Frozen ECC {ecc} is outside expected range [{frozen_ecc_min}, {frozen_ecc_max}].")
                except ValueError:
                    feedback.append("Could not parse ECC for frozen spacecraft.")
                    
                try:
                    aop = float(frozen_sc['AOP'])
                    if abs(aop - aop_1) <= aop_tol or abs(aop - aop_2) <= aop_tol:
                        total_score += scores["frozen_aop_correct"]
                        frozen_aop_ok = True
                        feedback.append(f"Frozen AOP is correct: {aop}")
                    else:
                        feedback.append(f"Frozen AOP {aop} is outside expected range (near 90 or 270).")
                except ValueError:
                    feedback.append("Could not parse AOP for frozen spacecraft.")
            else:
                feedback.append("Could not identify any spacecraft with ECC and AOP properties.")
                
            # 5. Check Gravity Model (find max degree across all force models)
            max_degree = 0
            for obj, props in sc_data.items():
                for k, v in props.items():
                    if 'Degree' in k:
                        try:
                            deg = int(v)
                            if deg > max_degree:
                                max_degree = deg
                        except ValueError:
                            pass
            
            if max_degree >= grav_deg_min:
                total_score += scores["gravity_model_adequate"]
                feedback.append(f"Gravity model degree adequate: {max_degree}")
            else:
                feedback.append(f"Gravity model degree {max_degree} is less than required {grav_deg_min}.")
                
            # 6. Check Drag and SRP
            has_drag = 'AtmosphereModel' in script_content or 'Drag' in script_content
            has_srp = re.search(r'\.SRP\s*=\s*On', script_content, re.IGNORECASE) is not None
            if has_drag and has_srp:
                total_score += scores["drag_and_srp"]
                feedback.append("Both Drag and SRP are configured in force model.")
            else:
                feedback.append(f"Force models missing: Drag={has_drag}, SRP={has_srp}.")
                
            # 7. Check Propagation duration
            prop_days = re.findall(r'ElapsedDays\s*=\s*([\d\.]+)', script_content)
            max_prop = max([float(d) for d in prop_days]) if prop_days else 0.0
            if max_prop >= prop_days_min:
                total_score += scores["propagation_60days"]
                feedback.append(f"Propagation duration adequate: {max_prop} days.")
            else:
                feedback.append(f"Propagation duration {max_prop} days is less than required {prop_days_min}.")

        except Exception as e:
            feedback.append(f"Error parsing script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 8. Check Analysis Report
    report_file = task_result.get('report_file', {})
    report_path = task_result.get('report_path', '/home/ga/GMAT_output/frozen_orbit_report.txt')
    
    if isinstance(report_file, dict) and report_file.get('exists'):
        temp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_rpt.name)
            with open(temp_rpt.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()
                
            # Find all required fields
            fields = {
                "frozen_ecc": None,
                "frozen_ecc_variation": None,
                "reference_ecc_variation": None,
                "frozen_alt_range_km": None,
                "reference_alt_range_km": None,
                "stability_ratio": None
            }
            
            for k in fields.keys():
                match = re.search(fr'{k}\s*:\s*([\d\.eE\+\-]+)', report_content, re.IGNORECASE)
                if match:
                    try:
                        fields[k] = float(match.group(1))
                    except ValueError:
                        pass
            
            valid_fields = sum(1 for v in fields.values() if v is not None)
            if valid_fields >= 4:
                total_score += scores["report_written"]
                feedback.append(f"Analysis report written ({valid_fields}/6 fields parsed).")
            else:
                feedback.append(f"Analysis report incomplete ({valid_fields}/6 fields parsed).")
                
            # Evaluate stability metrics
            f_ecc_var = fields.get("frozen_ecc_variation")
            if f_ecc_var is not None and f_ecc_var <= ecc_var_max:
                total_score += scores["frozen_ecc_stable"]
                feedback.append(f"Frozen ECC stable (variation {f_ecc_var} <= {ecc_var_max}).")
            elif f_ecc_var is not None:
                feedback.append(f"Frozen ECC variation too high: {f_ecc_var}.")
                
            f_alt_range = fields.get("frozen_alt_range_km")
            if f_alt_range is not None and f_alt_range <= alt_range_max:
                total_score += scores["frozen_alt_stable"]
                feedback.append(f"Frozen altitude stable (range {f_alt_range} km <= {alt_range_max} km).")
            elif f_alt_range is not None:
                feedback.append(f"Frozen altitude variation too high: {f_alt_range} km.")
                
            r_ecc_var = fields.get("reference_ecc_variation")
            if f_ecc_var is not None and r_ecc_var is not None and r_ecc_var > f_ecc_var:
                total_score += scores["reference_less_stable"]
                feedback.append(f"Reference orbit verified as less stable ({r_ecc_var} > {f_ecc_var}).")
                
            ratio = fields.get("stability_ratio")
            # compute fallback if missing
            if ratio is None and f_ecc_var and r_ecc_var and f_ecc_var > 0:
                ratio = r_ecc_var / f_ecc_var
                
            if ratio is not None and ratio >= stab_ratio_min:
                total_score += scores["stability_ratio_valid"]
                feedback.append(f"Stability ratio valid: {ratio} >= {stab_ratio_min}.")
            elif ratio is not None:
                feedback.append(f"Stability ratio {ratio} indicates orbit was not properly frozen.")
                
        except Exception as e:
            feedback.append(f"Error parsing report: {e}")
        finally:
            if os.path.exists(temp_rpt.name):
                os.unlink(temp_rpt.name)
    else:
        feedback.append("Analysis report not found.")

    # Check Pass Condition
    key_criteria_met = frozen_ecc_ok and frozen_aop_ok
    passed = (total_score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }