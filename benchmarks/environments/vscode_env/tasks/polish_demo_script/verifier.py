#!/usr/bin/env python3
"""
Verifier for Polish Demo Script task
"""

import sys
import os
import logging
import tempfile
import re
import subprocess
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_polish_demo_script(traj, env_info, task_info):
    """
    Verify that the demo script has been properly polished.
    
    Returns dict with:
        - passed: bool (True if all checks pass)
        - score: int (0-100)
        - feedback: str (detailed feedback)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    script_path = "/home/ga/workspace/demo_prep/data_processor.py"
    temp_dir = tempfile.mkdtemp(prefix='polish_verify_')
    
    try:
        # Copy file from container
        temp_script = os.path.join(temp_dir, "data_processor.py")
        try:
            copy_from_env(script_path, temp_script)
        except Exception as e:
            logger.error(f"Failed to copy script: {e}")
            return {"passed": False, "score": 0, "feedback": f"❌ Failed to copy script: {str(e)}"}
        
        # Read content
        if not os.path.exists(temp_script) or os.path.getsize(temp_script) == 0:
            return {"passed": False, "score": 0, "feedback": "❌ Script file not found or empty"}
        
        content = read_file_content(temp_script)
        if not content:
            return {"passed": False, "score": 0, "feedback": "❌ Failed to read script content"}
        
        checks_passed = 0
        total_checks = 5
        feedback_parts = []
        
        # ========== CHECK 1: Debug artifacts removed ==========
        logger.info("\n📋 Check 1: Debug artifacts removed")
        
        # Check for commented-out code (lines with # followed by actual code patterns)
        commented_code_pattern = r'^\s*#\s*(df|print|import|for|if|def|return|else|elif)\s*[=\(\[]'
        has_commented_code = bool(re.search(commented_code_pattern, content, re.MULTILINE))
        
        # Check for DEBUG print statements
        has_debug_prints = bool(re.search(r'print\s*\([^)]*DEBUG[^)]*\)', content, re.IGNORECASE))
        
        if has_commented_code:
            feedback_parts.append("❌ Found commented-out code lines")
            logger.info("  ❌ Found commented-out code")
        elif has_debug_prints:
            feedback_parts.append("❌ Found DEBUG print statements")
            logger.info("  ❌ Found DEBUG print statements")
        else:
            checks_passed += 1
            feedback_parts.append("✅ Debug artifacts removed")
            logger.info("  ✅ All debug artifacts removed")
        
        # ========== CHECK 2: Variable renaming ==========
        logger.info("\n📋 Check 2: Variable renaming")
        
        # Extract function body only (to avoid false positives)
        function_match = re.search(r'def process_orders.*?(?=\n(?:def |class |\Z))', content, re.DOTALL)
        if not function_match:
            feedback_parts.append("❌ Could not find process_orders function")
            logger.info("  ❌ Could not find process_orders function")
        else:
            function_body = function_match.group(0)
            
            # Count variable usages (after initial assignment)
            # For df2: should only appear once or twice max (initial assignment + maybe one more)
            df2_matches = re.findall(r'\bdf2\b', function_body)
            temp_x_matches = re.findall(r'\btemp_x\b', function_body)
            data_final_matches = re.findall(r'\bdata_final_v3\b', function_body)
            
            rename_issues = []
            if len(df2_matches) > 3:  # Allow for initial assignment and a couple uses
                rename_issues.append(f"'df2' still heavily used ({len(df2_matches)} occurrences)")
            if len(temp_x_matches) > 0:
                rename_issues.append(f"'temp_x' not renamed ({len(temp_x_matches)} occurrences)")
            if len(data_final_matches) > 0:
                rename_issues.append(f"'data_final_v3' not renamed ({len(data_final_matches)} occurrences)")
            
            if rename_issues:
                feedback_parts.append("❌ Variables not properly renamed: " + ", ".join(rename_issues))
                logger.info(f"  ❌ {'; '.join(rename_issues)}")
            else:
                checks_passed += 1
                feedback_parts.append("✅ Variables properly renamed")
                logger.info("  ✅ All variables properly renamed")
        
        # ========== CHECK 3: Constants extracted ==========
        logger.info("\n📋 Check 3: Constants extracted")
        
        # Find where function starts
        function_start = content.find('def process_orders')
        if function_start == -1:
            feedback_parts.append("❌ Could not find process_orders function")
            logger.info("  ❌ Could not find process_orders function")
        else:
            # Extract preamble (before function)
            preamble = content[:function_start]
            function_and_after = content[function_start:]
            
            # Look for module-level constants (ALL_CAPS pattern)
            constant_pattern = r'^[A-Z][A-Z0-9_]*\s*=\s*[\d.]+'
            constants = re.findall(constant_pattern, preamble, re.MULTILINE)
            
            # Check for magic numbers in function body
            # Be careful to avoid false positives in strings or comments
            magic_numbers_present = []
            if re.search(r'[\*\s]0\.15\b', function_and_after):
                magic_numbers_present.append("0.15")
            if re.search(r'[\*\s]0\.10\b', function_and_after):
                magic_numbers_present.append("0.10")
            if re.search(r'[\*\s]0\.05\b', function_and_after):
                magic_numbers_present.append("0.05")
            if re.search(r'>\s*1000\b', function_and_after):
                magic_numbers_present.append("1000")
            if re.search(r'>\s*500\b', function_and_after):
                magic_numbers_present.append("500")
            if re.search(r'>\s*100\b', function_and_after):
                magic_numbers_present.append("100")
            if re.search(r'days\s*=\s*30\b', function_and_after):
                magic_numbers_present.append("30")
            
            constants_issues = []
            if len(constants) < 5:
                constants_issues.append(f"Only {len(constants)} constants defined (expected at least 7)")
            if magic_numbers_present:
                constants_issues.append(f"Magic numbers still in function: {', '.join(magic_numbers_present)}")
            
            if constants_issues:
                feedback_parts.append("❌ Constants not properly extracted: " + "; ".join(constants_issues))
                logger.info(f"  ❌ {'; '.join(constants_issues)}")
            else:
                checks_passed += 1
                feedback_parts.append(f"✅ Constants extracted ({len(constants)} constants defined)")
                logger.info(f"  ✅ Constants properly extracted ({len(constants)} constants)")
        
        # ========== CHECK 4: Documentation added ==========
        logger.info("\n📋 Check 4: Documentation added")
        
        # Check for docstring
        has_docstring = bool(re.search(r'def process_orders[^:]*:\s*("""|\'\'\')', content))
        
        # Check for Args/Parameters and Returns sections in docstring
        has_args = bool(re.search(r'(Args?|Parameters?):', content))
        has_returns = bool(re.search(r'Returns?:', content))
        
        # Check for inline comments (# followed by text, but not commented-out code)
        # Look for comments after the initial part
        inline_comment_pattern = r'#\s+[A-Z].*'  # Comment starting with capital letter
        inline_comments = re.findall(inline_comment_pattern, content)
        has_inline_comments = len(inline_comments) >= 1
        
        doc_issues = []
        if not has_docstring:
            doc_issues.append("Missing function docstring")
        if not has_args:
            doc_issues.append("Docstring missing Args/Parameters section")
        if not has_returns:
            doc_issues.append("Docstring missing Returns section")
        if not has_inline_comments:
            doc_issues.append("Missing inline comments")
        
        if doc_issues:
            feedback_parts.append("❌ Documentation incomplete: " + "; ".join(doc_issues))
            logger.info(f"  ❌ {'; '.join(doc_issues)}")
        else:
            checks_passed += 1
            feedback_parts.append("✅ Documentation added")
            logger.info("  ✅ Documentation properly added")
        
        # ========== CHECK 5: Functionality preserved ==========
        logger.info("\n📋 Check 5: Functionality preserved")
        
        # Copy sample data file
        temp_csv = os.path.join(temp_dir, "sample_orders.csv")
        try:
            copy_from_env("/home/ga/workspace/demo_prep/sample_orders.csv", temp_csv)
        except:
            # Create minimal sample data if copy fails
            with open(temp_csv, 'w') as f:
                f.write("order_id,status,amount,order_date,customer_id\n")
                f.write("1001,completed,1200.00,2024-01-15,C001\n")
                f.write("1002,completed,450.00,2024-01-16,C002\n")
        
        # Try to execute the script
        test_code = f"""
import sys
sys.path.insert(0, '{temp_dir}')

try:
    from data_processor import process_orders
    result = process_orders('{temp_csv}')
    print("EXECUTION_SUCCESS")
    print(f"ROWS:{{len(result)}}")
    print(f"COLUMNS:{{','.join(result.columns.tolist())}}")
except Exception as e:
    print(f"EXECUTION_ERROR:{{e}}")
    import traceback
    traceback.print_exc()
"""
        
        try:
            result = subprocess.run(
                ['python3', '-c', test_code],
                capture_output=True,
                text=True,
                timeout=10,
                cwd=temp_dir
            )
            
            if "EXECUTION_SUCCESS" in result.stdout:
                # Check for expected columns
                if "discount" in result.stdout and "final_amount" in result.stdout:
                    checks_passed += 1
                    feedback_parts.append("✅ Script executes successfully with expected output")
                    logger.info("  ✅ Script executes successfully")
                else:
                    feedback_parts.append("❌ Script executes but output structure incorrect")
                    logger.info("  ❌ Output structure incorrect")
            else:
                error_msg = result.stdout + result.stderr
                feedback_parts.append(f"❌ Script execution failed: {error_msg[:100]}")
                logger.info(f"  ❌ Execution failed: {error_msg[:100]}")
        except subprocess.TimeoutExpired:
            feedback_parts.append("❌ Script execution timeout")
            logger.info("  ❌ Execution timeout")
        except Exception as e:
            feedback_parts.append(f"❌ Execution error: {str(e)[:100]}")
            logger.info(f"  ❌ Execution error: {e}")
        
        # ========== Final Score ==========
        score = int((checks_passed / total_checks) * 100)
        passed = (checks_passed == total_checks)
        
        logger.info(f"\n{'='*60}")
        logger.info(f"Final Score: {checks_passed}/{total_checks} checks passed ({score}%)")
        logger.info(f"{'='*60}")
        
        feedback = " | ".join(feedback_parts)
        
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
