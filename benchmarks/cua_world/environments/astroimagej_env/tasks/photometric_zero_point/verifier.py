#!/usr/bin/env python3
"""
Verifier for photometric_zero_point task in AstroImageJ.
"""

import base64
import json
import math
import os
import tempfile
import logging
import csv
import io

from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_photometric_zero_point(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # Check CSV
    csv_exists = result.get('csv_exists', False)
    csv_content_b64 = result.get('csv_content_b64', '')
    
    # Check JSON
    json_exists = result.get('json_exists', False)
    json_content_b64 = result.get('json_content_b64', '')
    
    csv_lines = []
    source_sky_vals = []
    sky_rad_in = None
    sky_rad_out = None
    radius = None
    
    if csv_exists and csv_content_b64:
        score += 20
        feedback.append("CSV exists")
        
        try:
            csv_str = base64.b64decode(csv_content_b64).decode('utf-8')
            if 'Source-Sky' in csv_str or 'Source_Minus_Sky' in csv_str:
                feedback.append("AIJ-specific columns found")
            
            # Use CSV parser that handles both tabs and commas
            try:
                dialect = csv.Sniffer().sniff(csv_str[:1024]) if len(csv_str) > 0 else csv.excel
            except:
                dialect = csv.excel
                
            reader = csv.DictReader(io.StringIO(csv_str), dialect=dialect)
            for row in reader:
                csv_lines.append(row)
                for k, v in row.items():
                    if k and ('Source-Sky' in k or 'Source_Minus_Sky' in k):
                        try:
                            source_sky_vals.append(float(v))
                        except ValueError:
                            pass
                    if k and 'Sky_Rad(in)' in k:
                        sky_rad_in = str(v).strip()
                    if k and 'Sky_Rad(out)' in k:
                        sky_rad_out = str(v).strip()
                    if k and 'Radius' in k:
                        radius = str(v).strip()
        except Exception as e:
            feedback.append(f"Error parsing CSV: {e}")
    else:
        feedback.append("CSV missing")
        
    # Strict aperture check
    try:
        if float(sky_rad_in) == 10.0 and float(sky_rad_out) == 20.0 and float(radius) == 6.0:
            score += 10
            feedback.append("Aperture settings correct")
        elif sky_rad_in or sky_rad_out:
            feedback.append(f"Aperture settings incorrect: rad={radius}, in={sky_rad_in}, out={sky_rad_out}")
    except (ValueError, TypeError):
        pass
        
    if len(source_sky_vals) >= 5:
        score += 10
        feedback.append(f"Five stars measured ({len(source_sky_vals)} found)")
    elif len(source_sky_vals) > 0:
        feedback.append(f"Only {len(source_sky_vals)} stars measured, expected 5")
        
    reported_zp = None
    if json_exists and json_content_b64:
        score += 10
        feedback.append("JSON report exists")
        try:
            json_str = base64.b64decode(json_content_b64).decode('utf-8')
            report_data = json.loads(json_str)
            reported_zp = report_data.get('average_zp')
            if reported_zp is not None:
                feedback.append(f"Reported ZP: {reported_zp}")
            else:
                feedback.append("JSON missing 'average_zp'")
        except Exception as e:
            feedback.append(f"Error parsing JSON report: {e}")
    else:
        feedback.append("JSON report missing")
        
    v_mags_data = result.get('v_mags_data', {})
    v_mags = v_mags_data.get('v_mags', [])
    
    math_passed = False
    if len(source_sky_vals) >= 5 and v_mags and reported_zp is not None:
        calculated_zps = []
        for i in range(min(5, len(v_mags))):
            flux = source_sky_vals[i]
            if flux > 0:
                m_inst = -2.5 * math.log10(flux)
                v_true = v_mags[i]
                calculated_zps.append(v_true - m_inst)
                
        if calculated_zps:
            expected_avg_zp = sum(calculated_zps) / len(calculated_zps)
            if abs(expected_avg_zp - float(reported_zp)) <= 0.05:
                score += 40
                math_passed = True
                feedback.append(f"Math accurate (expected ~{expected_avg_zp:.3f})")
            else:
                feedback.append(f"Math inaccurate: calculated {expected_avg_zp:.3f}, reported {reported_zp}")
    elif v_mags:
        feedback.append("Could not verify math due to missing data")
    else:
        feedback.append("Warning: Could not extract ground truth V mags")

    # VLM trajectory verification
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        vlm_prompt = (
            "This is a sequence of screenshots from a task where the user calculates a photometric zero point "
            "in AstroImageJ. Did the user open the Vcomb.fits image and interact with the AstroImageJ UI, "
            "such as placing apertures on the stars? Answer 'yes' or 'no' and briefly explain."
        )
        
        vlm_result = query_vlm(images=frames + [final], prompt=vlm_prompt)
        if vlm_result and "yes" in vlm_result.lower()[:30]:
            score += 10
            feedback.append("VLM confirms AstroImageJ usage")
        else:
            feedback.append("VLM did not confirm active AIJ usage")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        
    key_criteria_met = csv_exists and json_exists and math_passed
    passed = score >= 70 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "v_mags_found": v_mags,
            "source_sky_vals": source_sky_vals
        }
    }