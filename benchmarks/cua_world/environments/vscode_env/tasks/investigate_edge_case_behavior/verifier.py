#!/usr/bin/env python3
"""
Verifier for Edge Case Investigation task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_investigation_quality(traj, env_info, task_info):
    """
    Verify quality of edge case investigation.
    
    Checks:
    1. Documentation file (edge_case_analysis.md) exists with substantial content
    2. Code has added explanatory comments
    3. Code has debugging print statements
    4. Documentation discusses root causes with technical terms
    5. Multiple edge cases are discussed
    6. Documentation is structured (problem, observation, root cause, solution)
    7. Code is still syntactically valid Python
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='edge_case_verify_')

    try:
        # Copy exported files
        pricing_local = os.path.join(temp_dir, "pricing.py")
        analysis_local = os.path.join(temp_dir, "edge_case_analysis.md")
        
        try:
            copy_from_env("/tmp/pricing_investigated.py", pricing_local)
        except Exception as e:
            logger.warning(f"Failed to copy pricing.py: {e}")
        
        try:
            copy_from_env("/tmp/edge_case_analysis.md", analysis_local)
        except Exception as e:
            logger.warning(f"Failed to copy edge_case_analysis.md: {e}")

        score = 0
        max_score = 100
        feedback_parts = []
        
        # Read file contents
        pricing_content = ""
        analysis_content = ""
        
        if os.path.exists(pricing_local) and os.path.getsize(pricing_local) > 0:
            pricing_content = read_file_content(pricing_local)
        
        if os.path.exists(analysis_local) and os.path.getsize(analysis_local) > 0:
            analysis_content = read_file_content(analysis_local)
        
        # === Criterion 1: Documentation file exists with substantial content (25 points) ===
        if len(analysis_content) > 200:
            score += 25
            feedback_parts.append(f"✅ Documentation file exists ({len(analysis_content)} chars)")
            
            # Bonus: Check for structured sections (10 points)
            section_keywords = ['problem', 'observation', 'root cause', 'solution', 'proposed', 'fix']
            sections_found = sum(1 for kw in section_keywords if kw in analysis_content.lower())
            if sections_found >= 3:
                score += 10
                feedback_parts.append(f"✅ Well-structured analysis ({sections_found} sections)")
            elif sections_found >= 2:
                score += 5
                feedback_parts.append(f"⚠ Some structure ({sections_found} sections)")
        elif len(analysis_content) > 50:
            score += 10
            feedback_parts.append(f"⚠ Documentation file too brief ({len(analysis_content)} chars)")
        else:
            feedback_parts.append("❌ Missing or empty edge_case_analysis.md")
        
        # === Criterion 2: Code has added comments (15 points) ===
        if pricing_content:
            # Count comment lines (lines starting with # after stripping whitespace)
            comment_lines = [line for line in pricing_content.split('\n') 
                           if line.strip().startswith('#')]
            comment_count = len(comment_lines)
            
            # Original file has ~10 comment lines, look for significant increase
            if comment_count >= 15:
                score += 15
                feedback_parts.append(f"✅ Added explanatory comments ({comment_count} total)")
            elif comment_count >= 12:
                score += 10
                feedback_parts.append(f"⚠ Some comments added ({comment_count} total)")
            elif comment_count >= 10:
                score += 5
                feedback_parts.append(f"⚠ Minimal comments ({comment_count} total)")
            else:
                feedback_parts.append(f"❌ Insufficient comments ({comment_count} total)")
        else:
            feedback_parts.append("❌ Cannot analyze pricing.py (file missing or empty)")
        
        # === Criterion 3: Code has print statements for debugging (15 points) ===
        if pricing_content:
            print_count = pricing_content.lower().count('print(')
            
            if print_count >= 3:
                score += 15
                feedback_parts.append(f"✅ Added debugging print statements ({print_count})")
            elif print_count >= 2:
                score += 10
                feedback_parts.append(f"⚠ Some print statements ({print_count})")
            elif print_count >= 1:
                score += 5
                feedback_parts.append(f"⚠ Minimal debugging ({print_count} print)")
            else:
                feedback_parts.append("❌ No debugging print statements found")
        
        # === Criterion 4: Technical understanding shown (20 points) ===
        combined_content = (pricing_content + " " + analysis_content).lower()
        
        technical_keywords = [
            'type', 'validation', 'bounds', 'checking', 'coercion', 
            'edge case', 'negative', 'conversion', 'input', 'error',
            'TypeError', 'ValueError', 'exception', 'assert', 'constraint'
        ]
        keyword_matches = sum(1 for kw in technical_keywords if kw in combined_content)
        
        if keyword_matches >= 6:
            score += 20
            feedback_parts.append(f"✅ Strong technical understanding ({keyword_matches} concepts)")
        elif keyword_matches >= 4:
            score += 15
            feedback_parts.append(f"✅ Good technical insight ({keyword_matches} concepts)")
        elif keyword_matches >= 2:
            score += 10
            feedback_parts.append(f"⚠ Basic technical insight ({keyword_matches} concepts)")
        else:
            feedback_parts.append(f"❌ Limited technical insight ({keyword_matches} concepts)")
        
        # === Criterion 5: Multiple edge cases discussed (15 points) ===
        edge_case_indicators = [
            'negative', 'excessive', '>100', '100%', '150%',
            'string', 'str', 'type', 'zero', 'boundary'
        ]
        edge_mentions = sum(1 for indicator in edge_case_indicators if indicator in combined_content)
        
        if edge_mentions >= 4:
            score += 15
            feedback_parts.append(f"✅ Multiple edge cases analyzed ({edge_mentions} mentions)")
        elif edge_mentions >= 3:
            score += 10
            feedback_parts.append(f"⚠ Some edge cases discussed ({edge_mentions} mentions)")
        elif edge_mentions >= 1:
            score += 5
            feedback_parts.append(f"⚠ Limited edge case discussion ({edge_mentions} mentions)")
        else:
            feedback_parts.append("❌ No edge case discussion found")
        
        # === Criterion 6: Code is still valid Python (bonus check, no points but can fail) ===
        syntax_valid = True
        if pricing_content:
            try:
                compile(pricing_content, '<string>', 'exec')
            except SyntaxError as e:
                syntax_valid = False
                feedback_parts.append(f"⚠️ Syntax error in pricing.py: {str(e)}")
                score = max(0, score - 20)  # Penalty for broken syntax
        
        # Cap score at max
        score = min(score, max_score)
        
        # Determine pass/fail (threshold: 70%)
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Investigation verification - Score: {score}/{max_score}, Passed: {passed}")
        
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
