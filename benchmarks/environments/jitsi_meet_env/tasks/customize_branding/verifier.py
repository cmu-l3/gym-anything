#!/usr/bin/env python3
"""
Verifier for customize_branding task.

Verifies:
1. Configuration files contain correct JS overrides.
2. Docker container was restarted to apply changes.
3. Agent created a verification screenshot.
4. Agent wrote a correct report.
5. Branding strings are visible in the service (propagation check).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_branding(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_app_name = metadata.get('expected_app_name', 'FitConnect Pro')
    expected_remote_name = metadata.get('expected_remote_display_name', 'Fitness Participant')
    expected_subject = metadata.get('expected_subject', 'FitConnect Session')

    score = 0
    max_score = 100
    feedback = []

    # Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Verify custom-interface_config.js (30 points)
    interface_config_exists = result_data.get("interface_config_exists", False)
    if interface_config_exists:
        score += 5
        feedback.append("custom-interface_config.js created (+5).")
        
        # Analyze content
        temp_js = tempfile.NamedTemporaryFile(delete=False, suffix='.js')
        try:
            copy_from_env("/tmp/custom-interface_config.js", temp_js.name)
            with open(temp_js.name, 'r') as f:
                content = f.read()
                
            # Check APP_NAME
            if re.search(r"APP_NAME\s*:\s*['\"]" + re.escape(expected_app_name) + r"['\"]", content):
                score += 10
                feedback.append(f"APP_NAME set to '{expected_app_name}' (+10).")
            else:
                feedback.append(f"APP_NAME incorrect or missing.")

            # Check DEFAULT_REMOTE_DISPLAY_NAME
            if re.search(r"DEFAULT_REMOTE_DISPLAY_NAME\s*:\s*['\"]" + re.escape(expected_remote_name) + r"['\"]", content):
                score += 5
                feedback.append(f"DEFAULT_REMOTE_DISPLAY_NAME set correctly (+5).")
            else:
                feedback.append("DEFAULT_REMOTE_DISPLAY_NAME incorrect.")

            # Check Watermarks (false)
            if re.search(r"SHOW_JITSI_WATERMARK\s*:\s*false", content):
                score += 5
                feedback.append("SHOW_JITSI_WATERMARK disabled (+5).")
            
            if re.search(r"SHOW_WATERMARK_FOR_GUESTS\s*:\s*false", content):
                score += 5
                feedback.append("SHOW_WATERMARK_FOR_GUESTS disabled (+5).")
                
        except Exception as e:
            feedback.append(f"Error reading interface config: {e}")
        finally:
            if os.path.exists(temp_js.name):
                os.unlink(temp_js.name)
    else:
        feedback.append("custom-interface_config.js missing.")

    # 2. Verify custom-config.js (15 points)
    config_file_exists = result_data.get("config_file_exists", False)
    if config_file_exists:
        score += 5
        feedback.append("custom-config.js created (+5).")
        
        temp_cfg = tempfile.NamedTemporaryFile(delete=False, suffix='.js')
        try:
            copy_from_env("/tmp/custom-config.js", temp_cfg.name)
            with open(temp_cfg.name, 'r') as f:
                content = f.read()
            
            # Check defaultSubject
            # Note: config.defaultSubject = ... OR defaultSubject: ... in object
            if re.search(r"defaultSubject\s*[:=]\s*['\"]" + re.escape(expected_subject) + r"['\"]", content):
                score += 10
                feedback.append(f"defaultSubject set correctly (+10).")
            else:
                feedback.append("defaultSubject incorrect.")
        except Exception:
            pass
        finally:
            if os.path.exists(temp_cfg.name):
                os.unlink(temp_cfg.name)
    else:
        feedback.append("custom-config.js missing.")

    # 3. Verify Container Restart (20 points)
    if result_data.get("container_restarted", False):
        score += 20
        feedback.append("Web container restarted successfully (+20).")
    else:
        feedback.append("Web container was NOT restarted (changes not applied) (0).")

    # 4. Verify Service & Propagation (10 points)
    if result_data.get("service_available", False):
        score += 5
        feedback.append("Service is available (+5).")
        if result_data.get("branding_propagated", False):
            score += 5
            feedback.append("Branding changes visible on landing page (+5).")
        else:
            feedback.append("Branding changes NOT visible on landing page.")
    else:
        feedback.append("Service is down (crash?) (0).")

    # 5. Verify Visual Evidence (10 points)
    if result_data.get("evidence_screenshot_exists", False):
        score += 10
        feedback.append("Agent verification screenshot exists (+10).")
    else:
        feedback.append("Agent verification screenshot missing.")

    # 6. Verify Report (15 points)
    if result_data.get("report_exists", False):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/agent_report.txt", temp_report.name)
            with open(temp_report.name, 'r') as f:
                content = f.read()
            
            report_score = 0
            if expected_app_name in content: report_score += 5
            if expected_subject in content: report_score += 5
            if len(content) > 20: report_score += 5 # Basic content check
            
            score += report_score
            feedback.append(f"Report verification score: {report_score}/15.")
        except Exception:
            pass
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback.append("Agent report missing.")

    passed = (score >= 70) and result_data.get("container_restarted", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }