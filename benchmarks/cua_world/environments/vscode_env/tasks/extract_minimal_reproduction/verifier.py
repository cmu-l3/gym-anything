#!/usr/bin/env python3
"""
Verifier for Extract Minimal Reproduction task
"""

import sys
import os
import logging
import tempfile
import shutil
import re
import ast

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_minimal_reproduction(traj, env_info, task_info):
    """
    Verify that minimal reproducible example was created correctly.
    
    Checks:
    1. MRE file exists
    2. MRE is minimal (≤30 lines of code, excluding comments/blank)
    3. Only uses public libraries (numpy, numpy_financial)
    4. Contains problematic data pattern (small values near zero)
    5. Calls the buggy function (npf.irr or numpy_financial.irr)
    6. Has documentation (≥3 comment lines)
    7. Prints output to show the bug
    8. Bug report markdown exists
    9. Bug report has required sections
    10. MRE is syntactically valid Python
    11. Business logic was removed
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='mre_verify_')
    
    try:
        criteria_passed = 0
        total_criteria = 10
        feedback_parts = []
        
        # Paths
        mre_container_path = "/home/ga/workspace/portfolio_risk/bug_report_mre.py"
        report_container_path = "/home/ga/workspace/portfolio_risk/BUG_REPORT.md"
        
        mre_local_path = os.path.join(temp_dir, "bug_report_mre.py")
        report_local_path = os.path.join(temp_dir, "BUG_REPORT.md")
        
        # Criterion 1: Check that MRE file exists
        try:
            copy_from_env(mre_container_path, mre_local_path)
            if os.path.exists(mre_local_path) and os.path.getsize(mre_local_path) > 0:
                criteria_passed += 1
                feedback_parts.append("✅ MRE file created")
            else:
                feedback_parts.append("❌ MRE file not found or empty")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": " | ".join(feedback_parts)
                }
        except Exception as e:
            feedback_parts.append(f"❌ Failed to copy MRE file: {str(e)}")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Read MRE content
        mre_content = read_file_content(mre_local_path)
        
        # Criterion 2: Verify it's minimal (≤30 lines of actual code)
        lines = mre_content.split('\n')
        code_lines = [
            line for line in lines 
            if line.strip() and not line.strip().startswith('#')
        ]
        code_line_count = len(code_lines)
        
        if code_line_count <= 30:
            criteria_passed += 1
            feedback_parts.append(f"✅ MRE is minimal ({code_line_count} lines of code)")
        else:
            feedback_parts.append(f"❌ MRE too long: {code_line_count} lines (should be ≤30)")
        
        # Criterion 3: Verify only uses public libraries
        import_lines = [line for line in code_lines if 'import' in line.lower()]
        forbidden = ['company_internal', 'database', 'risk_models', 'pandas', 'Mock', 'portfolio']
        has_forbidden = False
        
        for imp in import_lines:
            if any(forbidden_lib.lower() in imp.lower() for forbidden_lib in forbidden):
                has_forbidden = True
                feedback_parts.append(f"❌ Contains internal/unnecessary dependency: {imp.strip()}")
                break
        
        if not has_forbidden and import_lines:
            criteria_passed += 1
            feedback_parts.append("✅ Uses only public libraries")
        elif not import_lines:
            feedback_parts.append("❌ No import statements found")
        
        # Criterion 4: Verify contains problematic data pattern (small values)
        has_small_values = False
        patterns = [
            r'0\.0+1',  # Matches 0.000001, 0.0001, etc.
            r'1e-\d+',  # Matches 1e-6, 1e-5, etc.
            r'0\.000001',  # Exact match
        ]
        
        for pattern in patterns:
            if re.search(pattern, mre_content):
                has_small_values = True
                break
        
        if has_small_values:
            criteria_passed += 1
            feedback_parts.append("✅ Contains problematic small-value pattern")
        else:
            feedback_parts.append("❌ Missing small-value pattern (e.g., 0.000001 or 1e-6)")
        
        # Criterion 5: Verify calls the problematic function
        calls_irr = (
            'npf.irr' in mre_content or 
            'numpy_financial.irr' in mre_content or
            '.irr(' in mre_content
        )
        
        if calls_irr:
            criteria_passed += 1
            feedback_parts.append("✅ Calls the problematic function (irr)")
        else:
            feedback_parts.append("❌ Does not call npf.irr() or numpy_financial.irr()")
        
        # Criterion 6: Verify has documentation (≥3 comment lines)
        comment_lines = [
            line for line in lines 
            if line.strip().startswith('#')
        ]
        
        if len(comment_lines) >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Has sufficient documentation ({len(comment_lines)} comment lines)")
        else:
            feedback_parts.append(f"❌ Insufficient documentation: {len(comment_lines)} comments (need ≥3)")
        
        # Criterion 7: Verify prints output
        if 'print' in mre_content.lower():
            criteria_passed += 1
            feedback_parts.append("✅ Prints output to demonstrate the bug")
        else:
            feedback_parts.append("❌ Missing print statement to show output")
        
        # Criterion 8: Check bug report markdown exists
        try:
            copy_from_env(report_container_path, report_local_path)
            if os.path.exists(report_local_path) and os.path.getsize(report_local_path) > 0:
                criteria_passed += 1
                feedback_parts.append("✅ Bug report file created")
            else:
                feedback_parts.append("❌ Bug report file not found or empty")
        except Exception as e:
            feedback_parts.append(f"❌ Bug report file not found: {str(e)[:50]}")
        
        # Criterion 9: Analyze bug report content
        if os.path.exists(report_local_path):
            report_content = read_file_content(report_local_path)
            report_lower = report_content.lower()
            
            required_keywords = {
                'title': ['bug', 'issue', 'irr', 'error', 'problem'],
                'environment': ['version', 'numpy', 'python'],
                'expected': ['expected', 'should'],
                'actual': ['actual', 'instead', 'but', 'however'],
                'reproduction': ['reproduce', 'run', 'python', 'steps']
            }
            
            sections_found = 0
            for section_name, keywords in required_keywords.items():
                if any(keyword in report_lower for keyword in keywords):
                    sections_found += 1
            
            if sections_found >= 4:  # At least 4 out of 5 sections
                criteria_passed += 1
                feedback_parts.append(f"✅ Bug report has required sections ({sections_found}/5)")
            else:
                feedback_parts.append(f"❌ Bug report missing sections ({sections_found}/5 found)")
        
        # Criterion 10: Verify MRE is syntactically valid Python
        try:
            ast.parse(mre_content)
            criteria_passed += 1
            feedback_parts.append("✅ MRE is syntactically valid Python")
        except SyntaxError as e:
            feedback_parts.append(f"❌ MRE has syntax error: {str(e)[:50]}")
        
        # Bonus check: Verify business logic was removed
        business_terms = [
            'PortfolioAnalyzer', 'risk_engine', 'database', 
            'RiskEngine', 'validate_result', 'aggregate',
            '_fetch_holdings', '_apply_risk', 'class '
        ]
        
        has_business_logic = any(term in mre_content for term in business_terms)
        
        if has_business_logic:
            # Don't penalize, just warn
            business_found = [term for term in business_terms if term in mre_content]
            feedback_parts.append(f"⚠️ May still contain business logic: {', '.join(business_found[:3])}")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80
        
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
