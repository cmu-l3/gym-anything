#!/usr/bin/env python3
"""
Verifier for Evolve API Schema task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_api_schema_evolution(traj, env_info, task_info):
    """
    Verify that email_verified field was added correctly with backward compatibility.

    Checks:
    1. Model: email_verified parameter with type hint and default value
    2. Model: to_dict() includes email_verified
    3. Schema: email_verified field in UserResponse
    4. Mock data: Both users have email_verified set
    5. Backward compatibility: Existing tests pass
    6. New test: Function exists
    7. New test: Verifies field presence and type
    8. New test: Passes when executed
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    workspace = "/home/ga/workspace/user-api"
    temp_dir = tempfile.mkdtemp(prefix='api_schema_verify_')

    try:
        checks = {
            "model_field_added": False,
            "model_has_default": False,
            "model_to_dict_updated": False,
            "schema_updated": False,
            "mock_data_updated": False,
            "existing_tests_pass": False,
            "new_test_added": False,
            "new_test_passes": False
        }

        feedback_parts = []

        # ===== Check 1-3: Model file (app/models.py) =====
        models_path = f"{workspace}/app/models.py"
        local_models = os.path.join(temp_dir, "models.py")

        try:
            copy_from_env(models_path, local_models)
            if os.path.exists(local_models):
                models_content = read_file_content(local_models)

                # Check 1: email_verified field exists with type hint
                if "email_verified" in models_content and ": bool" in models_content:
                    checks["model_field_added"] = True
                    feedback_parts.append("✅ Model: email_verified field added with type hint")

                    # Check 2: Field has default value (critical for backward compatibility)
                    # Look for patterns like: email_verified: bool = False or email_verified=False
                    default_patterns = [
                        r'email_verified\s*:\s*bool\s*=\s*False',
                        r'email_verified\s*=\s*False',
                    ]
                    has_default = any(re.search(pattern, models_content) for pattern in default_patterns)

                    if has_default:
                        checks["model_has_default"] = True
                        feedback_parts.append("✅ Model: email_verified has default value = False")
                    else:
                        feedback_parts.append("❌ Model: email_verified MISSING default value (breaks backward compatibility!)")
                else:
                    feedback_parts.append("❌ Model: email_verified field not found or missing type hint")

                # Check 3: to_dict() method includes email_verified
                to_dict_patterns = [
                    r'"email_verified"\s*:\s*self\.email_verified',
                    r"'email_verified'\s*:\s*self\.email_verified",
                ]
                has_to_dict = any(re.search(pattern, models_content) for pattern in to_dict_patterns)

                if has_to_dict:
                    checks["model_to_dict_updated"] = True
                    feedback_parts.append("✅ Model: to_dict() includes email_verified")
                else:
                    feedback_parts.append("❌ Model: to_dict() does not return email_verified field")
            else:
                feedback_parts.append("❌ Could not access app/models.py")
        except Exception as e:
            feedback_parts.append(f"❌ Error reading models.py: {str(e)[:50]}")

        # ===== Check 4: Schema file (app/schemas.py) =====
        schemas_path = f"{workspace}/app/schemas.py"
        local_schemas = os.path.join(temp_dir, "schemas.py")

        try:
            copy_from_env(schemas_path, local_schemas)
            if os.path.exists(local_schemas):
                schemas_content = read_file_content(local_schemas)

                # Check for email_verified: bool in UserResponse class
                if "email_verified" in schemas_content and ": bool" in schemas_content:
                    # More precise check: look for field declaration in class
                    schema_pattern = r'email_verified\s*:\s*bool'
                    if re.search(schema_pattern, schemas_content):
                        checks["schema_updated"] = True
                        feedback_parts.append("✅ Schema: email_verified: bool field added to UserResponse")
                    else:
                        feedback_parts.append("❌ Schema: email_verified field format incorrect")
                else:
                    feedback_parts.append("❌ Schema: email_verified field not found in UserResponse")
            else:
                feedback_parts.append("❌ Could not access app/schemas.py")
        except Exception as e:
            feedback_parts.append(f"❌ Error reading schemas.py: {str(e)[:50]}")

        # ===== Check 5: Mock data (app/main.py) =====
        main_path = f"{workspace}/app/main.py"
        local_main = os.path.join(temp_dir, "main.py")

        try:
            copy_from_env(main_path, local_main)
            if os.path.exists(local_main):
                main_content = read_file_content(local_main)

                # Count True and False values for email_verified in MOCK_USERS
                true_count = main_content.count("email_verified=True")
                false_count = main_content.count("email_verified=False")

                if true_count >= 1 and false_count >= 1:
                    checks["mock_data_updated"] = True
                    feedback_parts.append("✅ Mock data: Both users have email_verified set (mix of True/False)")
                elif true_count > 0 or false_count > 0:
                    feedback_parts.append("⚠️ Mock data: email_verified partially set (need both True and False cases)")
                else:
                    feedback_parts.append("❌ Mock data: email_verified not added to mock users")
            else:
                feedback_parts.append("❌ Could not access app/main.py")
        except Exception as e:
            feedback_parts.append(f"❌ Error reading main.py: {str(e)[:50]}")

        # ===== Check 6-8: Testing =====
        # Check 6 & 7: New test exists and content
        tests_path = f"{workspace}/tests/test_user_api.py"
        local_tests = os.path.join(temp_dir, "test_user_api.py")

        try:
            copy_from_env(tests_path, local_tests)
            if os.path.exists(local_tests):
                tests_content = read_file_content(local_tests)

                # Check if new test function exists
                if "def test_user_email_verified_field" in tests_content:
                    checks["new_test_added"] = True
                    feedback_parts.append("✅ New test: test_user_email_verified_field function exists")

                    # Check if test verifies the field (looks for assertions about email_verified)
                    test_checks_field = (
                        "email_verified" in tests_content and
                        ("assert" in tests_content or "isinstance" in tests_content)
                    )
                    if test_checks_field:
                        feedback_parts.append("✅ New test: Appears to verify email_verified field")
                    else:
                        feedback_parts.append("⚠️ New test: May not properly verify email_verified field")
                else:
                    feedback_parts.append("❌ New test: test_user_email_verified_field function not found")
            else:
                feedback_parts.append("❌ Could not access tests/test_user_api.py")
        except Exception as e:
            feedback_parts.append(f"❌ Error reading test_user_api.py: {str(e)[:50]}")

        # Check 8: Backward compatibility - existing tests still pass
        test_results_path = "/tmp/test_existing_success.txt"
        local_test_results = os.path.join(temp_dir, "test_existing_success.txt")

        try:
            copy_from_env(test_results_path, local_test_results)
            if os.path.exists(local_test_results):
                test_output = read_file_content(local_test_results)

                # Check exit code
                if "Existing test exit code: 0" in test_output:
                    checks["existing_tests_pass"] = True
                    feedback_parts.append("✅ CRITICAL: Existing tests pass (backward compatibility maintained)")
                else:
                    feedback_parts.append("❌ CRITICAL: Existing tests FAILED (backward compatibility broken!)")
            else:
                feedback_parts.append("⚠️ Could not verify existing tests (file not found)")
        except Exception as e:
            feedback_parts.append(f"⚠️ Could not verify existing tests: {str(e)[:50]}")

        # Check 9: New test passes
        new_test_results_path = "/tmp/test_new_test.txt"
        local_new_test = os.path.join(temp_dir, "test_new_test.txt")

        try:
            copy_from_env(new_test_results_path, local_new_test)
            if os.path.exists(local_new_test):
                new_test_output = read_file_content(local_new_test)

                if "New test exit code: 0" in new_test_output:
                    checks["new_test_passes"] = True
                    feedback_parts.append("✅ New test: Passes when executed")
                elif "not found" in new_test_output.lower():
                    feedback_parts.append("❌ New test: Function not found")
                else:
                    feedback_parts.append("❌ New test: Fails when executed")
            else:
                feedback_parts.append("⚠️ Could not verify new test execution")
        except Exception as e:
            feedback_parts.append(f"⚠️ Could not verify new test: {str(e)[:50]}")

        # ===== Calculate Score =====
        total_checks = len(checks)
        passed_checks = sum(checks.values())

        # Backward compatibility is CRITICAL - if broken, task fails
        if not checks["existing_tests_pass"]:
            feedback_parts.insert(0, "🚨 CRITICAL FAILURE: Broke backward compatibility!")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }

        # Default value is also critical
        if checks["model_field_added"] and not checks["model_has_default"]:
            feedback_parts.insert(0, "🚨 CRITICAL: Missing default value will break existing database records!")

        score = int((passed_checks / total_checks) * 100)
        passed = score >= 85  # Need 7/8 checks (85%)

        if passed:
            feedback_parts.insert(0, f"✅ SUCCESS: Added email_verified field with backward compatibility ({passed_checks}/{total_checks})")
        else:
            feedback_parts.insert(0, f"❌ INCOMPLETE: Only {passed_checks}/{total_checks} checks passed (need 85%)")

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
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
