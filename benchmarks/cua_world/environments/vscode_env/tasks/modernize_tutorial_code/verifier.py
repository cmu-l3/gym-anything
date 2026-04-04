#!/usr/bin/env python3
"""
Verifier for modernize_tutorial_code task
"""

import sys
import os
import re
import subprocess
import logging
import tempfile
import shutil
from pathlib import Path
from typing import Tuple, Dict, Any

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_pylint_score(output: str) -> float:
    """Extract score from pylint output"""
    match = re.search(r'Your code has been rated at ([\d.]+)/10', output)
    if match:
        return float(match.group(1))
    # Alternative format
    match = re.search(r'rated at ([\d.]+)/10', output)
    if match:
        return float(match.group(1))
    return 0.0


def count_test_results(pytest_output: str) -> Tuple[int, int]:
    """Extract passed and total test counts from pytest output"""
    passed = pytest_output.count(' PASSED')
    failed = pytest_output.count(' FAILED')
    total = passed + failed
    return passed, total


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify that the tutorial code was properly modernized
    
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available",
            "details": {}
        }

    workspace = "/home/ga/workspace/api_client"
    decorators_container_path = f"{workspace}/utils/decorators.py"
    
    # Create temp directory for verification
    temp_dir = tempfile.mkdtemp(prefix='modernize_verify_')
    
    try:
        # Create local workspace structure
        local_workspace = os.path.join(temp_dir, "api_client")
        os.makedirs(os.path.join(local_workspace, "utils"), exist_ok=True)
        os.makedirs(os.path.join(local_workspace, "tests"), exist_ok=True)
        
        # Copy necessary files
        files_to_copy = [
            ("utils/decorators.py", True),  # Required
            ("utils/__init__.py", False),
            ("tests/test_rate_limiter.py", False),
            ("tests/__init__.py", False),
            (".pylintrc", False),
            ("pyproject.toml", False),
        ]
        
        decorators_content = ""
        for rel_path, required in files_to_copy:
            src = f"{workspace}/{rel_path}"
            dst = os.path.join(local_workspace, rel_path)
            try:
                copy_from_env(src, dst)
                if rel_path == "utils/decorators.py" and os.path.exists(dst):
                    with open(dst, 'r', encoding='utf-8', errors='ignore') as f:
                        decorators_content = f.read()
            except Exception as e:
                if required:
                    return {
                        "passed": False,
                        "score": 0,
                        "feedback": f"❌ Required file not found: {rel_path}",
                        "details": {"error": str(e)}
                    }
                logger.warning(f"Could not copy {src}: {e}")
        
        # Check if file is too small or still template
        if len(decorators_content) < 200:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ decorators.py is too small or not implemented",
                "details": {"file_size": len(decorators_content)}
            }
        
        if "TODO:" in decorators_content and decorators_content.count("TODO") > decorators_content.count("def rate_limit"):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ decorators.py appears to still be template (contains TODO)",
                "details": {}
            }
        
        # Initialize scores
        functional_score = 0.0
        modernization_score = 0.0
        style_score = 0.0
        feedback_parts = []
        
        # ===== CHECK 1: FUNCTIONAL CORRECTNESS (50%) =====
        try:
            # Ensure pytest is available
            subprocess.run(["pip3", "install", "-q", "pytest"], 
                         check=False, capture_output=True, timeout=30)
            
            # Run tests
            test_result = subprocess.run(
                ["python3", "-m", "pytest", 
                 "tests/test_rate_limiter.py",
                 "-v", "--tb=short", "-p", "no:warnings"],
                cwd=local_workspace,
                capture_output=True,
                text=True,
                timeout=45
            )
            
            passed, total = count_test_results(test_result.stdout + test_result.stderr)
            
            if test_result.returncode == 0 and passed > 0:
                functional_score = 0.5
                feedback_parts.append(f"✅ All tests passed ({passed}/{total})")
            elif passed > 0 and total > 0:
                functional_score = 0.5 * (passed / total)
                feedback_parts.append(f"⚠️ Partial tests passed ({passed}/{total})")
            else:
                # Check for import errors or syntax errors
                error_output = test_result.stdout + test_result.stderr
                if "ImportError" in error_output or "ModuleNotFoundError" in error_output:
                    feedback_parts.append("❌ Import error: rate_limit not found or incorrect name")
                elif "SyntaxError" in error_output:
                    feedback_parts.append("❌ Syntax error in implementation")
                else:
                    feedback_parts.append(f"❌ Tests failed (0/{total})")
                    
        except subprocess.TimeoutExpired:
            feedback_parts.append("❌ Tests timed out (possible infinite loop)")
        except Exception as e:
            feedback_parts.append(f"❌ Tests failed to run: {str(e)[:80]}")
        
        # ===== CHECK 2: CODE MODERNIZATION (30%) =====
        modernization_checks = {
            "type_hints": False,
            "f_strings": False,
            "docstring": False,
            "logging": False,
            "no_print": False,
            "snake_case": False,
        }
        
        # Check for type hints (looking for Callable, ->, type annotations)
        if any(x in decorators_content for x in ["Callable", "-> ", ": int", ": float"]):
            if "->" in decorators_content:
                modernization_checks["type_hints"] = True
        
        # Check for f-strings
        if 'f"' in decorators_content or "f'" in decorators_content:
            modernization_checks["f_strings"] = True
        
        # Check for docstring (multi-line with Args/Returns or at least detailed)
        docstring_count = decorators_content.count('"""')
        if docstring_count >= 4:  # At least 2 complete docstrings
            modernization_checks["docstring"] = True
        elif docstring_count >= 2 and len(decorators_content.split('"""')[1]) > 50:
            modernization_checks["docstring"] = True
        
        # Check for logging usage
        if "logging." in decorators_content or "logger." in decorators_content:
            if "import logging" in decorators_content:
                modernization_checks["logging"] = True
        
        # Check no print statements
        if "print(" not in decorators_content:
            modernization_checks["no_print"] = True
        
        # Check for snake_case naming
        if "rate_limit" in decorators_content:
            if "rateLimiter" not in decorators_content and "maxCalls" not in decorators_content:
                if "max_calls" in decorators_content and "time_window" in decorators_content:
                    modernization_checks["snake_case"] = True
        
        passed_checks = [k for k, v in modernization_checks.items() if v]
        failed_checks = [k for k, v in modernization_checks.items() if not v]
        
        modernization_score = 0.3 * (len(passed_checks) / len(modernization_checks))
        
        if len(passed_checks) >= 4:
            feedback_parts.append(f"✅ Modernization ({len(passed_checks)}/6): {', '.join(passed_checks)}")
        else:
            feedback_parts.append(f"⚠️ Modernization ({len(passed_checks)}/6): missing {', '.join(failed_checks)}")
        
        # ===== CHECK 3: STYLE COMPLIANCE (20%) =====
        try:
            # Install style tools
            subprocess.run(["pip3", "install", "-q", "pylint", "black"], 
                         check=False, capture_output=True, timeout=30)
            
            local_decorators = os.path.join(local_workspace, "utils/decorators.py")
            local_pylintrc = os.path.join(local_workspace, ".pylintrc")
            
            # Run pylint
            pylint_cmd = ["python3", "-m", "pylint", local_decorators]
            if os.path.exists(local_pylintrc):
                pylint_cmd.extend(["--rcfile", local_pylintrc])
            
            pylint_result = subprocess.run(
                pylint_cmd,
                capture_output=True,
                text=True,
                timeout=20
            )
            
            pylint_score_value = extract_pylint_score(pylint_result.stdout)
            style_score += 0.15 * min(pylint_score_value / 8.0, 1.0)  # 15% for pylint >= 8.0
            
            # Run black check
            black_result = subprocess.run(
                ["python3", "-m", "black", "--check", "--quiet", local_decorators],
                capture_output=True,
                timeout=15
            )
            
            if black_result.returncode == 0:
                style_score += 0.05  # 5% for black compliance
                feedback_parts.append(f"✅ Style: pylint {pylint_score_value:.1f}/10, black ✓")
            else:
                feedback_parts.append(f"⚠️ Style: pylint {pylint_score_value:.1f}/10, black formatting needed")
                
        except subprocess.TimeoutExpired:
            feedback_parts.append("⚠️ Style checks timed out")
        except Exception as e:
            feedback_parts.append(f"⚠️ Style checks: {str(e)[:50]}")
        
        # ===== CALCULATE FINAL SCORE =====
        total_score = functional_score + modernization_score + style_score
        passed = total_score >= 0.75
        
        # Generate detailed feedback
        feedback = " | ".join(feedback_parts)
        
        details = {
            "functional_score": round(functional_score, 3),
            "modernization_score": round(modernization_score, 3),
            "style_score": round(style_score, 3),
            "total_score": round(total_score, 3),
            "modernization_checks": modernization_checks,
            "passed_modernization": passed_checks,
            "failed_modernization": failed_checks,
        }
        
        return {
            "passed": passed,
            "score": int(total_score * 100),
            "feedback": feedback,
            "details": details
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)[:100]}",
            "details": {"error": str(e)}
        }
    finally:
        # Clean up temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
