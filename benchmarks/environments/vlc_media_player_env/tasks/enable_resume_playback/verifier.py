#!/usr/bin/env python3
"""
Verifier for Enable Resume Playback task
Checks if VLC was configured to enable resume playback functionality
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_time_to_seconds(time_str):
    """Convert HH:MM:SS or MM:SS or SS to seconds"""
    try:
        time_str = str(time_str).strip()
        parts = time_str.split(':')
        
        if len(parts) == 3:  # HH:MM:SS
            h, m, s = map(float, parts)
            return h * 3600 + m * 60 + s
        elif len(parts) == 2:  # MM:SS
            m, s = map(float, parts)
            return m * 60 + s
        elif len(parts) == 1:  # Just seconds
            return float(parts[0])
        else:
            return 0.0
    except (ValueError, AttributeError):
        return 0.0


def check_resume_in_config(config_content):
    """
    Check if resume playback is enabled in VLC config content.
    Returns: (enabled: bool, value: str, details: str)
    """
    # Look for qt-continue setting
    # 0 = never resume, 1 = ask to resume, 2 = always resume
    qt_continue_match = re.search(r'^qt-continue\s*=\s*([0-9]+)', config_content, re.MULTILINE)
    
    if qt_continue_match:
        value = qt_continue_match.group(1)
        if value in ['1', '2']:
            mode = 'ask' if value == '1' else 'always'
            return True, value, f"Resume enabled: {mode} (qt-continue={value})"
        else:
            return False, value, f"Resume disabled (qt-continue={value})"
    
    # Check for alternative resume-related settings
    if re.search(r'qt.*continue|resume', config_content, re.IGNORECASE):
        return True, "unknown", "Resume-related settings found in config"
    
    return False, "0", "Resume setting not found in config"


def verify_optional_test_documentation(verification_content):
    """
    Verify optional test documentation file.
    Returns: (valid: bool, details: str)
    """
    try:
        # Look for stop position, resume position, and status
        stop_match = re.search(
            r'(?:stop|stopped|original|initial|close).*?(?:position|time|timestamp)[:\s]*([0-9:]+)',
            verification_content,
            re.IGNORECASE
        )
        resume_match = re.search(
            r'(?:resume|resumed|reopen|restart).*?(?:position|time|timestamp)[:\s]*([0-9:]+)',
            verification_content,
            re.IGNORECASE
        )
        status_match = re.search(
            r'(?:status|result|verification)[:\s]*(SUCCESS|PASS|OK|FAIL|FAILED)',
            verification_content,
            re.IGNORECASE
        )
        
        if stop_match and resume_match:
            stop_time = parse_time_to_seconds(stop_match.group(1))
            resume_time = parse_time_to_seconds(resume_match.group(1))
            time_diff = abs(resume_time - stop_time)
            
            # Positions should be close (within 5 seconds tolerance for resume)
            if time_diff <= 5.0:
                return True, f"Test documented: stop={stop_time:.1f}s, resume={resume_time:.1f}s (diff={time_diff:.1f}s)"
            else:
                return False, f"Test documented but positions don't match: stop={stop_time:.1f}s, resume={resume_time:.1f}s (diff={time_diff:.1f}s)"
        
        # Check for success keyword even without parsed positions
        if status_match and status_match.group(1).upper() in ['SUCCESS', 'PASS', 'OK']:
            return True, "Test documented with SUCCESS status"
        
        return False, "Test documentation incomplete or invalid"
        
    except Exception as e:
        logger.error(f"Error parsing verification file: {e}")
        return False, f"Error parsing verification file: {str(e)}"


def verify_enable_resume_playback(traj, env_info, task_info):
    """
    Verify enable resume playback task completion.
    
    Checks:
    1. Result JSON exists and is valid
    2. VLC config has resume playback enabled (qt-continue >= 1)
    3. (Optional bonus) Test was documented by agent
    
    Pass threshold: 70% (2/3 main criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Criterion 1: Result JSON exists and is valid
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_resume_result.json", temp_result.name)
        
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        criteria_met += 1
        feedback_parts.append("✅ Result file accessible")
        
        resume_enabled = result.get('resume_enabled', False)
        resume_value = result.get('resume_value', '0')
        config_found = result.get('config_found', False)
        test_documented = result.get('test_documented', False)
        
        logger.info(f"Result: resume_enabled={resume_enabled}, value={resume_value}, "
                   f"config_found={config_found}, test_documented={test_documented}")
        
        os.unlink(temp_result.name)
        
    except FileNotFoundError:
        logger.error("Result JSON not found")
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {str(e)}"}
    except Exception as e:
        logger.error(f"Error reading result: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}
    
    # Criterion 2: VLC config has resume enabled
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env("/tmp/vlc_resume_vlcrc.txt", temp_config.name)
        
        with open(temp_config.name, 'r', encoding='utf-8', errors='ignore') as f:
            config_content = f.read()
        
        config_enabled, config_value, config_details = check_resume_in_config(config_content)
        
        if config_enabled:
            criteria_met += 1.5  # Main criterion - give extra weight
            feedback_parts.append(f"✅ {config_details}")
        else:
            feedback_parts.append(f"❌ {config_details}")
        
        # Double-check against JSON result
        if resume_enabled and config_enabled:
            feedback_parts.append("✅ Resume enabled (confirmed in both JSON and config)")
        elif resume_enabled != config_enabled:
            logger.warning(f"Mismatch: JSON says {resume_enabled}, config analysis says {config_enabled}")
        
        os.unlink(temp_config.name)
        
    except FileNotFoundError:
        logger.warning("VLC config file not found")
        feedback_parts.append("⚠️ VLC config not accessible")
        # If JSON says it's enabled, give partial credit
        if resume_enabled:
            criteria_met += 0.5
            feedback_parts.append("⚠️ Resume enabled per JSON (config not verified)")
    except Exception as e:
        logger.error(f"Error reading config: {e}", exc_info=True)
        feedback_parts.append(f"⚠️ Error reading config: {str(e)}")
    
    # Criterion 3 (Optional bonus): Test documentation
    if test_documented:
        temp_verify = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/vlc_resume_verification.txt", temp_verify.name)
            
            with open(temp_verify.name, 'r', encoding='utf-8') as f:
                verify_content = f.read()
            
            test_valid, test_details = verify_optional_test_documentation(verify_content)
            
            if test_valid:
                criteria_met += 0.5  # Bonus points
                feedback_parts.append(f"✅ {test_details}")
            else:
                feedback_parts.append(f"ℹ️ {test_details}")
            
            os.unlink(temp_verify.name)
            
        except FileNotFoundError:
            feedback_parts.append("ℹ️ Test documentation mentioned but not found")
        except Exception as e:
            logger.warning(f"Error reading verification file: {e}")
            feedback_parts.append("ℹ️ Test documentation not readable")
    else:
        feedback_parts.append("ℹ️ Test documentation not provided (optional)")
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_resume_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score (criteria_met can exceed total_criteria due to weighted scoring)
    score = int(min((criteria_met / total_criteria) * 100, 100))
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Verification result: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }