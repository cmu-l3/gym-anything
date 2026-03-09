#!/usr/bin/env python3
"""
Verifier for Feature Flag Implementation task
"""

import sys
import os
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_feature_flag(traj, env_info, task_info):
    """
    Verify that feature flag has been properly implemented.
    
    Checks:
    1. .env file exists with USE_STRIPE_PAYMENT variable (1 point)
    2. app.py reads environment variable (0.5 points)
    3. app.py has conditional logic for payment processor selection (1.5 points)
    4. Logging added to track payment processor usage (1 point)
    5. Both code paths (Stripe and legacy) are properly implemented (1 point)
    
    Total: 5 points
    Pass threshold: 4 points (80%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    export_dir = "/tmp/feature_flag_export"
    temp_dir = tempfile.mkdtemp(prefix='feature_flag_verify_')
    
    try:
        # Copy exported files to local temp directory
        local_app_py = os.path.join(temp_dir, "app.py")
        local_env = os.path.join(temp_dir, ".env")
        
        try:
            copy_from_env(os.path.join(export_dir, "app.py"), local_app_py)
        except Exception as e:
            logger.warning(f"Failed to copy app.py: {e}")
            return {"passed": False, "score": 0, "feedback": f"❌ Failed to copy app.py: {str(e)}"}
        
        try:
            copy_from_env(os.path.join(export_dir, ".env"), local_env)
        except Exception as e:
            logger.warning(f"Failed to copy .env: {e}")
            # .env might not exist, we'll check below
        
        score = 0.0
        max_score = 5.0
        feedback_parts = []
        
        # Check 1: .env file exists with USE_STRIPE_PAYMENT variable (1 point)
        env_exists = os.path.exists(local_env)
        env_has_flag = False
        
        if env_exists:
            try:
                with open(local_env, 'r') as f:
                    env_content = f.read()
                
                # Check if NOT_FOUND marker is present
                if "NOT_FOUND" in env_content:
                    feedback_parts.append("❌ .env file not found in workspace")
                else:
                    # Check for USE_STRIPE_PAYMENT variable
                    if re.search(r'USE_STRIPE_PAYMENT\s*=\s*(true|false|True|False|TRUE|FALSE|0|1)', env_content, re.IGNORECASE):
                        score += 1.0
                        env_has_flag = True
                        # Extract the value
                        match = re.search(r'USE_STRIPE_PAYMENT\s*=\s*(\S+)', env_content, re.IGNORECASE)
                        if match:
                            flag_value = match.group(1)
                            feedback_parts.append(f"✅ .env file exists with USE_STRIPE_PAYMENT={flag_value}")
                        else:
                            feedback_parts.append("✅ .env file exists with USE_STRIPE_PAYMENT variable")
                    else:
                        feedback_parts.append("❌ .env file exists but doesn't contain USE_STRIPE_PAYMENT variable")
            except Exception as e:
                feedback_parts.append(f"❌ Error reading .env file: {e}")
        else:
            feedback_parts.append("❌ .env file not found")
        
        # Check 2-5: Analyze app.py
        if not os.path.exists(local_app_py):
            feedback_parts.append("❌ app.py not found")
            feedback = "\n".join(feedback_parts)
            feedback += f"\n\nScore: {score}/{max_score} ({score/max_score*100:.0f}%)"
            return {"passed": False, "score": 0, "feedback": feedback}
        
        try:
            with open(local_app_py, 'r') as f:
                app_content = f.read()
        except Exception as e:
            feedback_parts.append(f"❌ Error reading app.py: {e}")
            feedback = "\n".join(feedback_parts)
            feedback += f"\n\nScore: {score}/{max_score} ({score/max_score*100:.0f}%)"
            return {"passed": False, "score": 0, "feedback": feedback}
        
        # Check if NOT_FOUND marker is present
        if "NOT_FOUND" in app_content:
            feedback_parts.append("❌ app.py not found in workspace")
            feedback = "\n".join(feedback_parts)
            feedback += f"\n\nScore: {score}/{max_score} ({score/max_score*100:.0f}%)"
            return {"passed": False, "score": 0, "feedback": feedback}
        
        # Check 2: app.py reads environment variable (0.5 points)
        has_dotenv = bool(re.search(r'from\s+dotenv\s+import\s+load_dotenv', app_content))
        has_load_dotenv = bool(re.search(r'load_dotenv\s*\(\s*\)', app_content))
        has_getenv = bool(re.search(r'os\.getenv|os\.environ', app_content))
        has_stripe_env_check = bool(re.search(r'USE_STRIPE', app_content, re.IGNORECASE))
        
        if (has_dotenv or has_load_dotenv or has_getenv) and has_stripe_env_check:
            score += 0.5
            feedback_parts.append("✅ app.py reads environment variable")
        elif has_getenv or has_stripe_env_check:
            score += 0.25
            feedback_parts.append("⚠️  app.py partially reads environment (may be missing dotenv setup)")
        else:
            feedback_parts.append("❌ app.py doesn't read USE_STRIPE_PAYMENT environment variable")
        
        # Check 3: app.py has conditional logic (1.5 points)
        # Look for if-else or ternary operator with stripe/legacy
        has_if_statement = bool(re.search(r'if\s+.*stripe.*:|if\s+.*flag.*:|if\s+.*enabled.*:', app_content, re.IGNORECASE))
        has_else_statement = bool(re.search(r'else\s*:', app_content))
        has_stripe_call = 'process_payment_stripe' in app_content
        has_legacy_call = 'process_payment_legacy' in app_content
        
        # Check for ternary operator pattern
        has_ternary = bool(re.search(r'=.*if.*else.*', app_content))
        
        # Check if both payment methods are in conditional context
        conditional_payment = (has_if_statement or has_ternary) and has_stripe_call and has_legacy_call
        
        if conditional_payment and (has_else_statement or has_ternary):
            score += 1.5
            feedback_parts.append("✅ Conditional logic properly implements both payment paths")
        elif conditional_payment:
            score += 1.0
            feedback_parts.append("⚠️  Conditional logic present but may be incomplete")
        elif has_stripe_call and has_legacy_call:
            score += 0.5
            feedback_parts.append("⚠️  Both payment processors referenced but no clear conditional logic")
        else:
            feedback_parts.append("❌ No proper conditional logic for payment processor selection")
        
        # Check 4: Logging added (1 point)
        # Look for logger.info, logger.debug, or logger.warning with payment-related content
        has_logging = bool(re.search(r'logger\.(info|debug|warning|error)\s*\(.*payment', app_content, re.IGNORECASE))
        has_stripe_log = bool(re.search(r'logger\.(info|debug|warning)\s*\(.*stripe', app_content, re.IGNORECASE))
        has_legacy_log = bool(re.search(r'logger\.(info|debug|warning)\s*\(.*legacy', app_content, re.IGNORECASE))
        
        if has_logging and (has_stripe_log or has_legacy_log):
            score += 1.0
            feedback_parts.append("✅ Logging added to track payment processor usage")
        elif has_logging:
            score += 0.5
            feedback_parts.append("⚠️  Some logging present but may not distinguish processors")
        else:
            feedback_parts.append("❌ No logging detected for payment processor selection")
        
        # Check 5: Code quality - both paths functional (1 point)
        # Check for syntax errors
        try:
            compile(app_content, 'app.py', 'exec')
            code_compiles = True
        except SyntaxError as e:
            code_compiles = False
            feedback_parts.append(f"❌ Syntax error in app.py: {e}")
        
        if code_compiles:
            # Check that both processors are called in checkout function
            checkout_match = re.search(r'def checkout\(.*?\):.*?(?=\ndef|\Z)', app_content, re.DOTALL)
            if checkout_match:
                checkout_code = checkout_match.group(0)
                
                has_stripe_in_checkout = 'process_payment_stripe' in checkout_code
                has_legacy_in_checkout = 'process_payment_legacy' in checkout_code
                has_return_or_jsonify = 'return' in checkout_code or 'jsonify' in checkout_code
                
                if has_stripe_in_checkout and has_legacy_in_checkout and has_return_or_jsonify:
                    score += 1.0
                    feedback_parts.append("✅ Both payment processors integrated in checkout endpoint")
                elif has_stripe_in_checkout or has_legacy_in_checkout:
                    score += 0.5
                    feedback_parts.append("⚠️  Only one payment processor found in checkout endpoint")
                else:
                    feedback_parts.append("❌ Payment processors not properly integrated in checkout")
            else:
                # Could not find checkout function
                if has_stripe_call or has_legacy_call:
                    score += 0.5
                    feedback_parts.append("⚠️  Payment processors present but checkout function structure unclear")
                else:
                    feedback_parts.append("❌ Checkout function not found or not modified")
        
        # Calculate final result
        normalized_score = score / max_score
        passed = score >= 4.0  # Need at least 80% to pass
        
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\nScore: {score}/{max_score} ({normalized_score*100:.0f}%)"
        
        if passed:
            feedback += "\n\n✅ Task completed successfully! Feature flag implementation is functional."
        else:
            feedback += "\n\n❌ Task incomplete. Review the requirements and ensure all components are implemented."
            feedback += "\n\nRequired components:"
            feedback += "\n  1. .env file with USE_STRIPE_PAYMENT variable"
            feedback += "\n  2. app.py reads the environment variable"
            feedback += "\n  3. Conditional logic to choose payment processor"
            feedback += "\n  4. Logging to track which processor is used"
            feedback += "\n  5. Both code paths properly implemented"
        
        return {
            "passed": passed,
            "score": int(normalized_score * 100),
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
