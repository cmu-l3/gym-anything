#!/usr/bin/env python3
"""
Verifier for lunar_orbiter_earth_eclipse@1

The agent must configure a multi-body EclipseLocator (Earth + Luna) in GMAT,
propagate across the March 2025 Total Lunar Eclipse, and extract the maximum
Umbra duration (which should be > 3500 seconds due to Earth's massive shadow).

Scoring (Total: 100 points, Pass >= 60):
- script_modified (10): Script modified during task.
- eclipse_locator_configured (20): EclipseLocator defined with BOTH Earth and Luna.
- propagation_added (10): Propagate command added to script.
- report_generated (20): EclipseReport.txt generated.
- json_created (10): eclipse_analysis.json exists and is valid JSON.
- earth_shadow_detected (30): max_umbra_duration_seconds >= 3500.

Pass condition: score >= 60 AND earth_shadow_detected AND report_generated
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_lunar_orbiter_earth_eclipse(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_expected_duration = metadata.get('min_expected_duration_sec', 3500.0)

    scores = {
        "script_modified": 10,
        "eclipse_locator_configured": 20,
        "propagation_added": 10,
        "report_generated": 20,
        "json_created": 10,
        "earth_shadow_detected": 30,
    }

    total_score = 0
    feedback = []
    
    earth_shadow_detected = False
    report_generated = False

    # 1. Load task result JSON
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

    # 2. Check Script modifications
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_modified"]
        feedback.append("Script modified during task.")
    else:
        feedback.append("Script not modified during task.")

    script_path = task_result.get('script_path', '/home/ga/Documents/missions/lunar_baseline.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Check for EclipseLocator
            has_locator = "Create EclipseLocator" in script_content
            # Look for OccultingBodies containing both Earth and Luna
            occulting_match = re.search(r'\.OccultingBodies\s*=\s*\{([^}]+)\}', script_content)
            
            if has_locator and occulting_match:
                bodies = occulting_match.group(1).lower()
                if 'earth' in bodies and 'luna' in bodies:
                    total_score += scores["eclipse_locator_configured"]
                    feedback.append("EclipseLocator correctly configured with Earth and Luna.")
                elif 'earth' in bodies or 'luna' in bodies:
                    total_score += scores["eclipse_locator_configured"] // 2
                    feedback.append("EclipseLocator found, but missing either Earth or Luna as occulting bodies.")
            elif has_locator:
                feedback.append("EclipseLocator found, but OccultingBodies not properly configured.")
            else:
                feedback.append("No EclipseLocator found in script.")

            # Check for propagation
            if re.search(r'\bPropagate\b', script_content):
                total_score += scores["propagation_added"]
                feedback.append("Propagate command found in script.")
            else:
                feedback.append("No Propagate command found.")

        except Exception as e:
            feedback.append(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("Baseline script file missing.")

    # 3. Check EclipseReport
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('exists') and report_file.get('size', 0) > 0:
        total_score += scores["report_generated"]
        report_generated = True
        feedback.append("EclipseReport.txt generated successfully.")
    else:
        feedback.append("EclipseReport.txt not found or empty.")

    # 4. Check JSON Analysis File
    json_file = task_result.get('json_file', {})
    json_path = task_result.get('json_path', '/home/ga/GMAT_output/eclipse_analysis.json')
    
    if isinstance(json_file, dict) and json_file.get('exists'):
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(json_path, temp_json.name)
            with open(temp_json.name, 'r') as f:
                analysis_data = json.load(f)
            
            total_score += scores["json_created"]
            feedback.append("eclipse_analysis.json successfully parsed.")

            duration = analysis_data.get('max_umbra_duration_seconds')
            if duration is not None:
                try:
                    duration_float = float(duration)
                    if duration_float >= min_expected_duration:
                        total_score += scores["earth_shadow_detected"]
                        earth_shadow_detected = True
                        feedback.append(f"Correct duration found: {duration_float}s (>= {min_expected_duration}s). Multi-body shadow detected!")
                    else:
                        feedback.append(f"Reported duration {duration_float}s is too short (expected >= {min_expected_duration}s). Earth shadow was missed.")
                except ValueError:
                    feedback.append("Value for max_umbra_duration_seconds is not a valid number.")
            else:
                feedback.append("Key 'max_umbra_duration_seconds' not found in JSON.")

        except json.JSONDecodeError:
            feedback.append("eclipse_analysis.json is not valid JSON.")
        except Exception as e:
            feedback.append(f"Error reading eclipse_analysis.json: {e}")
        finally:
            if os.path.exists(temp_json.name):
                os.unlink(temp_json.name)
    else:
        feedback.append("eclipse_analysis.json not found.")

    # Determine Pass/Fail
    key_criteria_met = earth_shadow_detected and report_generated
    passed = (total_score >= 60) and key_criteria_met

    if not key_criteria_met:
        feedback.append("FAIL: Did not meet critical criteria (Earth shadow duration detection AND report generation).")

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }