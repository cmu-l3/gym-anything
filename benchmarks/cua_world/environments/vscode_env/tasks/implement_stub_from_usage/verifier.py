#!/usr/bin/env python3
"""
Verifier for Implement Stub From Usage task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def to_snake_case(name):
    """Convert camelCase to snake_case"""
    s1 = re.sub('(.)([A-Z][a-z]+)', r'\1_\2', name)
    return re.sub('([a-z0-9])([A-Z])', r'\1_\2', s1).lower()


def verify_stub_implementation(traj, env_info, task_info):
    """
    Verify that the stub function was correctly implemented.
    
    Tests multiple criteria:
    1. Function is implemented (no NotImplementedError)
    2. Adds default values for missing keys
    3. Converts camelCase to snake_case
    4. Strict mode raises ValueError on invalid data
    5. Lenient mode handles invalid data gracefully
    6. Preserves and normalizes valid values
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/workspace/config_manager/utils.py"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.py', mode='w+')
    temp_dir = tempfile.mkdtemp(prefix='stub_verify_')

    try:
        # Copy utils.py from container
        copy_from_env(container_path, temp_file.name)
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ utils.py not found or empty"
            }

        # Read the file content for basic checks
        with open(temp_file.name, 'r') as f:
            content = f.read()

        feedback_parts = []
        criteria_passed = 0
        total_criteria = 6

        # Pre-check: Basic function existence
        if 'def validate_and_normalize_config' not in content:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Function 'validate_and_normalize_config' not found in utils.py"
            }

        # Try to import and execute the function
        import importlib.util
        spec = importlib.util.spec_from_file_location("utils_module", temp_file.name)
        utils_module = importlib.util.module_from_spec(spec)
        
        try:
            spec.loader.exec_module(utils_module)
            validate_fn = utils_module.validate_and_normalize_config
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to load utils.py: {str(e)}"
            }

        # Criterion 1: Function no longer raises NotImplementedError
        try:
            result = validate_fn({})
            if not isinstance(result, dict):
                feedback_parts.append("❌ Function should return a dict")
                return {
                    "passed": False,
                    "score": 10,
                    "feedback": " | ".join(feedback_parts)
                }
            criteria_passed += 1
            feedback_parts.append("✅ Function implemented (returns dict)")
        except NotImplementedError:
            feedback_parts.append("❌ Function still raises NotImplementedError (stub not implemented)")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        except Exception as e:
            feedback_parts.append(f"❌ Function raised unexpected error on empty dict: {type(e).__name__}")
            return {
                "passed": False,
                "score": 5,
                "feedback": " | ".join(feedback_parts)
            }

        # Criterion 2: Test default values on empty config
        try:
            result = validate_fn({})
            required_keys = ['version', 'timeout', 'retry_limit']
            missing = [k for k in required_keys if k not in result]
            
            if not missing:
                # Check if default values are correct
                correct_defaults = (
                    result.get('version') == '1.0' and
                    result.get('timeout') == 30 and
                    result.get('retry_limit') == 3
                )
                if correct_defaults:
                    criteria_passed += 1
                    feedback_parts.append("✅ Adds correct default values (version='1.0', timeout=30, retry_limit=3)")
                else:
                    feedback_parts.append(f"⚠️ Has default keys but values incorrect: {result}")
            else:
                feedback_parts.append(f"❌ Missing default keys: {missing}")
        except Exception as e:
            feedback_parts.append(f"❌ Failed on empty config: {type(e).__name__}")

        # Criterion 3: Test key normalization (camelCase → snake_case)
        try:
            result = validate_fn({'retryLimit': 5, 'maxTimeout': 100})
            
            has_snake_case = 'retry_limit' in result
            no_camel_case = 'retryLimit' not in result
            
            if has_snake_case and no_camel_case:
                criteria_passed += 1
                feedback_parts.append("✅ Converts camelCase to snake_case correctly")
            elif has_snake_case:
                feedback_parts.append("⚠️ Converts camelCase but doesn't remove original keys")
            else:
                feedback_parts.append("❌ Does not normalize camelCase keys to snake_case")
        except Exception as e:
            feedback_parts.append(f"❌ Key normalization test failed: {type(e).__name__}")

        # Criterion 4: Test strict_mode=True with invalid data
        try:
            validate_fn({'timeout': 'invalid_string'}, strict_mode=True)
            feedback_parts.append("❌ Strict mode should raise ValueError on invalid types")
        except ValueError:
            criteria_passed += 1
            feedback_parts.append("✅ Strict mode correctly raises ValueError on invalid data")
        except Exception as e:
            feedback_parts.append(f"⚠️ Strict mode raised {type(e).__name__} instead of ValueError")

        # Criterion 5: Test strict_mode=False handles invalid data gracefully
        try:
            result = validate_fn({'timeout': 'invalid_string'}, strict_mode=False)
            
            if isinstance(result, dict) and isinstance(result.get('timeout'), int):
                criteria_passed += 1
                feedback_parts.append("✅ Lenient mode uses defaults for invalid values")
            else:
                feedback_parts.append("❌ Lenient mode should replace invalid values with defaults")
        except Exception as e:
            feedback_parts.append(f"❌ Lenient mode should not raise exceptions: {type(e).__name__}")

        # Criterion 6: Test that valid values are preserved and normalized
        try:
            result = validate_fn({'timeout': 60, 'retryLimit': 5, 'customKey': 'value'})
            
            checks_passed = 0
            if result.get('timeout') == 60:
                checks_passed += 1
            if result.get('retry_limit') == 5:
                checks_passed += 1
            if 'version' in result:  # Should add missing default
                checks_passed += 1
            
            if checks_passed >= 3:
                criteria_passed += 1
                feedback_parts.append("✅ Preserves valid values and adds missing defaults")
            else:
                feedback_parts.append(f"⚠️ Some valid values not handled correctly ({checks_passed}/3 checks)")
        except Exception as e:
            feedback_parts.append(f"❌ Failed on valid config: {type(e).__name__}")

        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold (at least 4/6 criteria)

        # Add summary message
        if score >= 95:
            summary = "🎉 Excellent implementation! All criteria met."
        elif passed:
            summary = f"✓ Good implementation ({criteria_passed}/{total_criteria} criteria passed)"
        else:
            summary = f"❌ Implementation incomplete ({criteria_passed}/{total_criteria} criteria passed, need {int(0.7 * total_criteria)})"

        feedback_parts.insert(0, summary)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
