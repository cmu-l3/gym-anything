#!/usr/bin/env python3
"""
Verifier for export_stargazing_passes task.

Task: Export text-based satellite pass predictions using specific criteria.
  1. Add Cherry Springs ground station (41.6615 N, 77.8232 W, 701m)
  2. Adjust predictions Minimum Elevation to 20 degrees
  3. Generate and export ISS passes to ~/Documents/ISS_passes.txt
  4. Generate and export CSS passes to ~/Documents/CSS_passes.txt

Scoring (100 points, pass >= 70):
  - Cherry Springs QTH correct: 20 pts
  - Minimum elevation set to 20 degrees: 20 pts
  - ISS_passes.txt exported correctly (anti-gaming content checks): 30 pts
  - CSS_passes.txt exported correctly (anti-gaming content checks): 30 pts

Anti-Gaming Strategy:
The verifier copies the generated text files out of the environment and parses 
their contents. A real GPredict export will contain target satellite names, tabular 
headers ("AOS", "LOS"), and either the specified observer location name or coordinates. 
Empty files or hallucinated text files will fail the content checks.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_file_contents(env_info, remote_path, keywords, required_headers, location_keywords):
    """
    Copies the file from the container and verifies its contents.
    Returns (is_valid, reason)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return False, "copy_from_env unavailable"

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env(remote_path, temp_path)
        with open(temp_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()

        if not content.strip():
            return False, "File is empty"

        content_upper = content.upper()

        # 1. Check for satellite identification keywords
        target_found = any(k.upper() in content_upper for k in keywords)
        if not target_found:
            return False, f"Missing satellite target identifiers (expected one of: {keywords})"

        # 2. Check for tabular headers specific to GPredict prediction exports
        for header in required_headers:
            if header.upper() not in content_upper:
                return False, f"Missing prediction header: '{header}'"

        # 3. Check for location references (proves they set up the location)
        loc_found = any(k.upper() in content_upper for k in location_keywords)
        if not loc_found:
            return False, "Missing observer location reference (Name or Coordinates)"

        return True, "Valid GPredict prediction export"

    except Exception as e:
        return False, f"Error reading file contents: {e}"
    finally:
        try:
            os.unlink(temp_path)
        except Exception:
            pass


def verify_export_stargazing_passes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_lat = metadata.get('qth_lat', 41.6615)
    expected_lon = metadata.get('qth_lon', -77.8232)
    expected_alt = metadata.get('qth_alt', 701)
    expected_min_el = str(metadata.get('min_elevation', 20))

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/export_stargazing_passes_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        with open(temp_path, 'r') as f:
            result = json.load(f)

    except (json.JSONDecodeError, FileNotFoundError) as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        try:
            os.unlink(temp_path)
        except Exception:
            pass

    score = 0
    feedback_parts = []

    # --- Criterion 1: Cherry Springs QTH Configuration (20 pts) ---
    if result.get('qth_exists'):
        lat_ok = _close_enough(result.get('qth_lat', ''), expected_lat, 0.1)
        lon_ok = _close_enough(result.get('qth_lon', ''), expected_lon, 0.1)
        alt_ok = _close_enough(result.get('qth_alt', ''), expected_alt, 50)

        if lat_ok and lon_ok and alt_ok:
            score += 20
            feedback_parts.append("Cherry Springs ground station correctly configured")
        elif lat_ok and lon_ok:
            score += 15
            feedback_parts.append(f"Cherry Springs coordinates OK, but altitude incorrect ({result.get('qth_alt')}m)")
        else:
            score += 5
            feedback_parts.append(f"Cherry Springs station found, but coordinates incorrect (lat={result.get('qth_lat')}, lon={result.get('qth_lon')})")
    else:
        feedback_parts.append("Cherry Springs ground station NOT FOUND")

    # --- Criterion 2: Minimum Elevation Preference (20 pts) ---
    min_el = result.get('min_el_val', '').strip()
    if min_el == expected_min_el:
        score += 20
        feedback_parts.append(f"Minimum elevation correctly set to {min_el} degrees")
    elif min_el:
        feedback_parts.append(f"Minimum elevation incorrectly set to {min_el} (expected {expected_min_el})")
    else:
        feedback_parts.append("Minimum elevation preference not set/found")

    # --- Criteria 3 & 4: Exported Text Files (30 pts each) ---
    req_columns = metadata.get('required_columns', ['AOS', 'LOS', 'Max El'])
    loc_keywords = ["Cherry", "Springs", "41.6", "77.8"]

    iss_file = result.get('iss_file', {})
    css_file = result.get('css_file', {})

    iss_keywords = metadata.get('iss_keywords', ['ISS', 'ZARYA', '25544'])
    css_keywords = metadata.get('css_keywords', ['CSS', 'TIANHE', '48274'])

    # Evaluate ISS export
    if iss_file.get('exists'):
        if not iss_file.get('created_during_task'):
            feedback_parts.append("ISS_passes.txt existed before task (Not generated by agent)")
        else:
            is_valid, reason = verify_file_contents(env_info, metadata.get('iss_export_path', '/home/ga/Documents/ISS_passes.txt'), iss_keywords, req_columns, loc_keywords)
            if is_valid:
                score += 30
                feedback_parts.append("ISS predictions successfully exported and validated")
            else:
                feedback_parts.append(f"ISS_passes.txt failed validation: {reason}")
    else:
        feedback_parts.append("ISS_passes.txt was NOT exported")

    # Evaluate CSS export
    if css_file.get('exists'):
        if not css_file.get('created_during_task'):
            feedback_parts.append("CSS_passes.txt existed before task (Not generated by agent)")
        else:
            is_valid, reason = verify_file_contents(env_info, metadata.get('css_export_path', '/home/ga/Documents/CSS_passes.txt'), css_keywords, req_columns, loc_keywords)
            if is_valid:
                score += 30
                feedback_parts.append("CSS predictions successfully exported and validated")
            else:
                feedback_parts.append(f"CSS_passes.txt failed validation: {reason}")
    else:
        feedback_parts.append("CSS_passes.txt was NOT exported")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }