#!/usr/bin/env python3
"""
Verifier for Update Breaking Dependency task
Checks that axios was upgraded and breaking changes were addressed
"""

import sys
import os
import json
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_dependency_update(traj, env_info, task_info):
    """
    Verify that dependency was updated and code was migrated.
    
    Checks:
    1. package.json updated to axios 1.x
    2. node_modules has axios 1.x installed (optional, may not be installed yet)
    3. Old error.request pattern removed from payment-client.js
    4. New error.code === 'ERR_NETWORK' pattern present
    5. Old error.request pattern removed from api-client.js
    6. error.response handling preserved
    
    Args:
        traj: Trajectory data
        env_info: Environment info with copy_from_env function
        task_info: Task information
    
    Returns:
        dict: Verification result with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    workspace = "/home/ga/workspace/api-project"
    temp_dir = tempfile.mkdtemp(prefix='axios_verify_')
    
    try:
        checks_passed = 0
        total_checks = 6
        feedback_parts = []
        
        # Check 1: package.json updated to axios 1.x
        try:
            package_json_path = f"{workspace}/package.json"
            temp_package = os.path.join(temp_dir, "package.json")
            copy_from_env(package_json_path, temp_package)
            
            if not os.path.exists(temp_package) or os.path.getsize(temp_package) == 0:
                feedback_parts.append("❌ Check 1: package.json not found or empty")
            else:
                with open(temp_package, 'r', encoding='utf-8') as f:
                    package_data = json.load(f)
                
                axios_version = package_data.get('dependencies', {}).get('axios', '')
                logger.info(f"Found axios version in package.json: {axios_version}")
                
                # Check if version is 1.x or later
                # Accept: "^1.6.0", "~1.6.0", "1.6.0", "1.x", "^1.x", etc.
                version_valid = False
                if axios_version:
                    # Remove ^ or ~ prefix
                    clean_version = axios_version.lstrip('^~')
                    # Check if starts with 1. or is "1.x"
                    if clean_version.startswith('1.') or clean_version == '1.x':
                        # For 1.x.y, check that x >= 6
                        if '.' in clean_version:
                            parts = clean_version.split('.')
                            if len(parts) >= 2:
                                try:
                                    major = int(parts[0])
                                    minor = int(parts[1]) if parts[1] != 'x' else 6
                                    if major == 1 and minor >= 6:
                                        version_valid = True
                                    elif major > 1:
                                        version_valid = True
                                except ValueError:
                                    pass
                        else:
                            version_valid = True
                
                if version_valid:
                    logger.info("✓ Check 1 passed: package.json updated to axios 1.x")
                    feedback_parts.append(f"✅ Check 1: package.json updated to axios {axios_version}")
                    checks_passed += 1
                else:
                    logger.error(f"✗ Check 1 failed: axios version is {axios_version}, expected ^1.6.0 or later")
                    feedback_parts.append(f"❌ Check 1: axios version is {axios_version}, expected ^1.6.0 or later")
        except Exception as e:
            logger.error(f"✗ Check 1 failed: Could not verify package.json: {e}")
            feedback_parts.append(f"❌ Check 1: Error reading package.json - {str(e)[:50]}")
        
        # Check 2: node_modules installed correctly (optional check, weight is lower)
        try:
            installed_package_path = f"{workspace}/node_modules/axios/package.json"
            temp_installed = os.path.join(temp_dir, "axios_installed.json")
            copy_from_env(installed_package_path, temp_installed)
            
            if os.path.exists(temp_installed) and os.path.getsize(temp_installed) > 0:
                with open(temp_installed, 'r', encoding='utf-8') as f:
                    installed_data = json.load(f)
                
                installed_version = installed_data.get('version', '')
                logger.info(f"Installed axios version: {installed_version}")
                
                # Parse version
                if installed_version:
                    parts = installed_version.split('.')
                    if len(parts) >= 1:
                        try:
                            major_version = int(parts[0])
                            if major_version >= 1:
                                logger.info("✓ Check 2 passed: axios 1.x+ installed in node_modules")
                                feedback_parts.append(f"✅ Check 2: axios {installed_version} installed")
                                checks_passed += 1
                            else:
                                feedback_parts.append(f"❌ Check 2: installed version is {installed_version}")
                        except ValueError:
                            feedback_parts.append(f"⚠️ Check 2: Could not parse installed version {installed_version}")
        except Exception as e:
            logger.warning(f"Check 2 skipped: Could not verify installed version: {e}")
            feedback_parts.append("⚠️ Check 2: npm install may not have run yet (skipped)")
        
        # Check 3 & 4: Code migration in payment-client.js
        try:
            payment_client_path = f"{workspace}/lib/payment-client.js"
            temp_payment = os.path.join(temp_dir, "payment-client.js")
            copy_from_env(payment_client_path, temp_payment)
            
            if not os.path.exists(temp_payment) or os.path.getsize(temp_payment) == 0:
                feedback_parts.append("❌ Checks 3-4: payment-client.js not found")
            else:
                with open(temp_payment, 'r', encoding='utf-8') as f:
                    payment_content = f.read()
                
                # Check 3: Old pattern removed
                # Look for "error.request" but not "error.request" as part of error.response
                old_pattern_matches = re.findall(r'(?<!\.response)\.request(?!\w)', payment_content)
                # More specifically, look for the problematic pattern: "if (error.request)" or "else if (error.request)"
                problematic_checks = re.findall(r'if\s*\(\s*\w+\.request\s*\)', payment_content)
                
                old_pattern_count = len(problematic_checks)
                
                if old_pattern_count == 0:
                    logger.info("✓ Check 3 passed: No 'error.request' checks in payment-client.js")
                    feedback_parts.append("✅ Check 3: Old error.request pattern removed from payment-client.js")
                    checks_passed += 1
                else:
                    logger.error(f"✗ Check 3 failed: Found {old_pattern_count} instances of 'error.request' checks")
                    feedback_parts.append(f"❌ Check 3: Found {old_pattern_count} old error.request checks in payment-client.js")
                
                # Check 4: New pattern exists
                new_pattern_count = len(re.findall(r"\.code\s*===\s*['\"]ERR_NETWORK['\"]", payment_content))
                if new_pattern_count >= 1:
                    logger.info(f"✓ Check 4 passed: Found {new_pattern_count} new axios 1.x error patterns")
                    feedback_parts.append(f"✅ Check 4: New error.code pattern found in payment-client.js ({new_pattern_count} instances)")
                    checks_passed += 1
                else:
                    logger.error("✗ Check 4 failed: No new axios 1.x error.code checks found")
                    feedback_parts.append("❌ Check 4: No new error.code === 'ERR_NETWORK' pattern in payment-client.js")
        except Exception as e:
            logger.error(f"✗ Checks 3-4 failed: Could not verify payment-client.js: {e}")
            feedback_parts.append(f"❌ Checks 3-4: Error reading payment-client.js - {str(e)[:50]}")
        
        # Check 5: Code migration in api-client.js
        try:
            api_client_path = f"{workspace}/middleware/api-client.js"
            temp_api = os.path.join(temp_dir, "api-client.js")
            copy_from_env(api_client_path, temp_api)
            
            if not os.path.exists(temp_api) or os.path.getsize(temp_api) == 0:
                feedback_parts.append("❌ Check 5: api-client.js not found")
            else:
                with open(temp_api, 'r', encoding='utf-8') as f:
                    api_content = f.read()
                
                # Check that old pattern removed or migration done
                old_pattern_api = len(re.findall(r'if\s*\(\s*\w+\.request\s*\)', api_content))
                
                # Should have new pattern OR should have removed the old problematic pattern
                has_new_pattern = "error.code" in api_content or "ERR_NETWORK" in api_content
                has_migration = has_new_pattern or old_pattern_api == 0
                
                if has_migration:
                    logger.info("✓ Check 5 passed: api-client.js migrated")
                    if has_new_pattern:
                        feedback_parts.append("✅ Check 5: api-client.js migrated with new error.code pattern")
                    else:
                        feedback_parts.append("✅ Check 5: api-client.js old pattern removed")
                    checks_passed += 1
                else:
                    logger.error("✗ Check 5 failed: api-client.js not properly migrated")
                    feedback_parts.append(f"❌ Check 5: api-client.js still has {old_pattern_api} old error.request checks")
        except Exception as e:
            logger.error(f"✗ Check 5 failed: Could not verify api-client.js: {e}")
            feedback_parts.append(f"❌ Check 5: Error reading api-client.js - {str(e)[:50]}")
        
        # Check 6: error.response handling preserved (should still be there)
        try:
            # Verify that server error handling (error.response) still works
            response_checks = len(re.findall(r'\.response', payment_content))
            if response_checks >= 2:  # Should still check error.response
                logger.info(f"✓ Check 6 passed: error.response handling preserved ({response_checks} checks)")
                feedback_parts.append(f"✅ Check 6: error.response handling preserved")
                checks_passed += 1
            else:
                logger.warning("Check 6: error.response handling may have been removed")
                feedback_parts.append("⚠️ Check 6: error.response checks seem reduced (may be OK)")
                # Don't fail completely for this
                checks_passed += 0.5
        except:
            logger.error("✗ Check 6 failed: Could not verify error.response handling")
            feedback_parts.append("❌ Check 6: Could not verify error.response handling")
        
        # Calculate score
        score = int((checks_passed / total_checks) * 100)
        
        # Require at least 4/6 checks (67%) to pass
        # This allows for npm install not being run, but core migration must be done
        passed = checks_passed >= 4
        
        # Summary
        logger.info(f"\n{'='*60}")
        logger.info(f"Verification Summary: {checks_passed}/{total_checks} checks passed")
        logger.info(f"{'='*60}")
        
        feedback = " | ".join(feedback_parts)
        
        if passed:
            logger.info("✅ Task completed successfully!")
        else:
            logger.error("❌ Task incomplete - need to update dependency and migrate code")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
