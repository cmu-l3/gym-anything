#!/usr/bin/env python3
"""
Verifier for Bug Reproduction task
"""

import sys
import os
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_reproduction(traj, env_info, task_info):
    """
    Verify bug reproduction task completion.
    
    Checks:
    1. Test CSV file exists
    2. CSV has proper structure with headers
    3. CSV contains empty fields (problematic pattern)
    4. Reproduction document exists
    5. Document contains clear steps
    6. Document contains error message
    7. Document includes command to execute
    8. Overall documentation quality
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='bug_repro_verify_')

    try:
        score = 0.0
        max_score = 8.0
        feedback = []

        # Copy exported files
        csv_local = os.path.join(temp_dir, "test_csv.csv")
        doc_local = os.path.join(temp_dir, "reproduction.md")

        try:
            copy_from_env("/tmp/test_csv_file.csv", csv_local)
        except Exception as e:
            logger.warning(f"Failed to copy CSV file: {e}")

        try:
            copy_from_env("/tmp/reproduction_doc.md", doc_local)
        except Exception as e:
            logger.warning(f"Failed to copy documentation file: {e}")

        # ===== CSV FILE VALIDATION =====
        csv_exists = os.path.exists(csv_local) and os.path.getsize(csv_local) > 0
        
        if csv_exists:
            score += 1.0
            feedback.append("✅ Test CSV file found")
            
            csv_content = read_file_content(csv_local)
            lines = csv_content.strip().split('\n')
            
            # Check for proper CSV structure
            if len(lines) >= 2 and ',' in lines[0]:
                score += 1.0
                feedback.append("✅ CSV has proper structure with headers")
                
                # Check header contains relevant fields
                header = lines[0].lower()
                has_relevant_fields = any(
                    keyword in header 
                    for keyword in ['quantity', 'price', 'amount', 'value', 'id', 'product']
                )
                if has_relevant_fields:
                    feedback.append("  ↳ Headers include relevant fields")
            else:
                feedback.append("❌ CSV structure appears malformed")
            
            # Check for empty fields (key to bug reproduction)
            has_empty_fields = (
                ',,' in csv_content or 
                ',\n' in csv_content or 
                csv_content.count(',\r\n') > 0 or
                '\t\t' in csv_content
            )
            
            # Alternative check: look for lines with fewer values
            empty_field_found = False
            if len(lines) >= 2:
                header_commas = lines[0].count(',')
                for line in lines[1:]:
                    line_commas = line.count(',')
                    if line_commas >= header_commas:
                        # Check for consecutive commas or trailing comma
                        if ',,' in line or line.rstrip().endswith(','):
                            empty_field_found = True
                            break
            
            if has_empty_fields or empty_field_found:
                score += 1.5
                feedback.append("✅ CSV contains empty fields that trigger the bug")
            else:
                feedback.append("❌ CSV missing empty fields described in bug report")
        else:
            feedback.append("❌ Test CSV file not found")

        # ===== DOCUMENTATION VALIDATION =====
        doc_exists = os.path.exists(doc_local) and os.path.getsize(doc_local) > 0
        
        if doc_exists:
            score += 1.0
            feedback.append("✅ Reproduction document found")
            
            doc_content = read_file_content(doc_local)
            doc_lower = doc_content.lower()
            
            # Check for reproduction steps
            has_steps = (
                'steps to reproduce' in doc_lower or
                'reproduction steps' in doc_lower or
                'how to reproduce' in doc_lower or
                ('1.' in doc_content and '2.' in doc_content) or
                (doc_content.count('- ') >= 3) or
                ('step 1' in doc_lower and 'step 2' in doc_lower)
            )
            
            if has_steps:
                score += 1.5
                feedback.append("✅ Clear reproduction steps documented")
            else:
                feedback.append("❌ Reproduction steps not clearly documented")
            
            # Check for error message/output
            error_keywords = [
                'error', 'valueerror', 'traceback', 'exception', 
                'float', 'convert', 'could not convert', 'failed'
            ]
            has_error = any(keyword in doc_lower for keyword in error_keywords)
            
            # Check for code blocks that might contain error
            has_code_block = '```' in doc_content or 'traceback' in doc_lower
            if has_error:
                score += 1.0
                feedback.append("✅ Documentation mentions the observed error")
            else:
                feedback.append("❌ Documentation does not describe the error output")

            has_command = any(term in doc_lower for term in [
                'python', 'npm', 'node', 'run', 'execute', 'command'
            ])
            if has_command:
                score += 1.0
                feedback.append("✅ Documentation includes how to run the reproduction")
            else:
                feedback.append("❌ Documentation does not include an execution command")

            if has_code_block and len(doc_content.strip()) >= 200:
                score += 1.0
                feedback.append("✅ Documentation quality is sufficient")
            else:
                feedback.append("❌ Documentation is too thin or lacks concrete output snippets")
        else:
            feedback.append("❌ Reproduction document not found")

        passed = score >= 6.0 and csv_exists and doc_exists
        return {
            "passed": passed,
            "score": int((score / max_score) * 100),
            "feedback": " | ".join(feedback),
        }
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
