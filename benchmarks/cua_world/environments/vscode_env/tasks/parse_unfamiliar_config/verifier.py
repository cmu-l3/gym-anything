#!/usr/bin/env python3
"""
Verifier for Parse Unfamiliar Config task
"""

import sys
import os
import logging
import tempfile
import shutil

# Ensure PyYAML is available
try:
    import yaml
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyyaml"])
    import yaml

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_config_modification(traj, env_info, task_info):
    """
    Verify that the gateway configuration was modified correctly.
    
    Checks:
    1. File exists and is valid YAML
    2. payment-service.rate_limit.bkt_sz = 200
    3. payment-service.rate_limit.thr_win = 30
    4. payment-service.rate_limit.priority_bypass = true
    5. Other service configs unchanged (spot check)
    6. File structure intact
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_config_')
    
    try:
        # Copy the modified config file
        container_path = "/tmp/gateway_config_modified.yaml"
        local_path = os.path.join(temp_dir, "gateway_config.yaml")
        
        try:
            copy_from_env(container_path, local_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy config file: {str(e)}"}
        
        # Check file exists and has content
        if not os.path.exists(local_path) or os.path.getsize(local_path) == 0:
            return {"passed": False, "score": 0, "feedback": "Config file not found or empty"}
        
        # Parse YAML
        try:
            with open(local_path, 'r', encoding='utf-8') as f:
                config = yaml.safe_load(f)
        except yaml.YAMLError as e:
            return {"passed": False, "score": 0, "feedback": f"Invalid YAML syntax: {str(e)}"}
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: File is valid YAML (already checked above)
        criteria_passed += 1
        feedback_parts.append("✅ Valid YAML syntax")
        
        # Navigate to payment-service
        if 'services' not in config:
            return {"passed": False, "score": int((criteria_passed / total_criteria) * 100), 
                   "feedback": "❌ Missing 'services' key in config"}
        
        if 'payment-service' not in config['services']:
            return {"passed": False, "score": int((criteria_passed / total_criteria) * 100),
                   "feedback": "❌ Missing 'payment-service' in services"}
        
        payment_config = config['services']['payment-service']
        
        if 'rate_limit' not in payment_config:
            return {"passed": False, "score": int((criteria_passed / total_criteria) * 100),
                   "feedback": "❌ Missing 'rate_limit' in payment-service"}
        
        rate_limit = payment_config['rate_limit']
        
        # Criterion 2: bkt_sz = 200
        bkt_sz_value = rate_limit.get('bkt_sz')
        if bkt_sz_value == 200:
            criteria_passed += 1
            feedback_parts.append("✅ bkt_sz = 200")
        else:
            feedback_parts.append(f"❌ bkt_sz expected 200, got {bkt_sz_value}")
        
        # Criterion 3: thr_win = 30
        thr_win_value = rate_limit.get('thr_win')
        if thr_win_value == 30:
            criteria_passed += 1
            feedback_parts.append("✅ thr_win = 30")
        else:
            feedback_parts.append(f"❌ thr_win expected 30, got {thr_win_value}")
        
        # Criterion 4: priority_bypass = true
        priority_bypass_value = rate_limit.get('priority_bypass')
        if priority_bypass_value is True:
            criteria_passed += 1
            feedback_parts.append("✅ priority_bypass = true")
        else:
            feedback_parts.append(f"❌ priority_bypass expected true, got {priority_bypass_value}")
        
        # Criterion 5: Check that unchanged fields remain correct
        enabled_value = rate_limit.get('enabled')
        rps_value = rate_limit.get('requests_per_second')
        
        unchanged_correct = True
        if enabled_value is not True:
            feedback_parts.append(f"⚠️ payment-service.rate_limit.enabled changed (expected true, got {enabled_value})")
            unchanged_correct = False
        if rps_value != 50:
            feedback_parts.append(f"⚠️ payment-service.rate_limit.requests_per_second changed (expected 50, got {rps_value})")
            unchanged_correct = False
        
        if unchanged_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Other payment-service rate_limit fields unchanged")
        
        # Criterion 6: Spot check other services weren't modified
        other_services_ok = True
        
        # Check auth-service rate limit
        if 'auth-service' in config['services']:
            auth_rl = config['services']['auth-service'].get('rate_limit', {})
            auth_bkt_sz = auth_rl.get('bkt_sz')
            if auth_bkt_sz != 100:
                feedback_parts.append(f"❌ auth-service modified (bkt_sz expected 100, got {auth_bkt_sz})")
                other_services_ok = False
        
        # Check user-service rate limit
        if 'user-service' in config['services']:
            user_rl = config['services']['user-service'].get('rate_limit', {})
            user_bkt_sz = user_rl.get('bkt_sz')
            if user_bkt_sz != 30:
                feedback_parts.append(f"❌ user-service modified (bkt_sz expected 30, got {user_bkt_sz})")
                other_services_ok = False
        
        if other_services_ok:
            criteria_passed += 1
            feedback_parts.append("✅ Other service configurations unchanged")
        
        # Additional check: ensure retry_policy in payment-service wasn't touched
        if 'retry_policy' in payment_config:
            retry_policy = payment_config['retry_policy']
            if retry_policy.get('max_attempts') != 3:
                feedback_parts.append("⚠️ payment-service retry_policy was modified")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 85  # 85% threshold (5/6 criteria)
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "metadata": {
                "bkt_sz": bkt_sz_value,
                "thr_win": thr_win_value,
                "priority_bypass": priority_bypass_value,
                "criteria_passed": f"{criteria_passed}/{total_criteria}"
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
