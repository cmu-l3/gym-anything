#!/usr/bin/env python3
"""
Verifier for Optimize Database Query task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sql_query(traj, env_info, task_info):
    """
    Verify that SQL query file was created correctly.
    
    Checks:
    1. File exists at correct location
    2. File has sufficient content (>100 chars)
    3. Contains SELECT statement
    4. Contains FROM clause
    5. Contains at least 3 JOIN clauses
    6. Contains GROUP BY clause
    7. Contains ORDER BY clause
    8. Contains DESC keyword
    9. Contains LIMIT clause
    10. Contains aggregate functions (SUM or COUNT)
    11. References required tables (orders, products, categories, order_items)
    12. SQL keywords are uppercase
    13. Has proper formatting (indentation, multi-line)
    14. Contains at least one comment
    
    Pass threshold: 85% (11/13 main criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/workspace/analytics_db/top_products_by_category.sql"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.sql', mode='w+')
    
    try:
        # Copy file from container
        copy_from_env(container_path, temp_file.name)
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"File not found or empty: {container_path}"
            }
        
        # Read file content
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Check minimum content length
        if len(content.strip()) < 100:
            return {
                "passed": False,
                "score": 5,
                "feedback": f"File exists but content is too short ({len(content)} characters, expected at least 100)"
            }
        
        content_upper = content.upper()
        
        # Initialize checks dictionary
        checks = {}
        feedback_parts = []
        
        # Check 1: SELECT statement
        checks['has_select'] = "SELECT" in content_upper
        if checks['has_select']:
            feedback_parts.append("✅ SELECT statement present")
        else:
            feedback_parts.append("❌ SELECT statement missing")
        
        # Check 2: FROM clause
        checks['has_from'] = "FROM" in content_upper
        if checks['has_from']:
            feedback_parts.append("✅ FROM clause present")
        else:
            feedback_parts.append("❌ FROM clause missing")
        
        # Check 3: At least 3 JOIN clauses
        join_count = content_upper.count("JOIN")
        checks['has_joins'] = join_count >= 3
        if checks['has_joins']:
            feedback_parts.append(f"✅ Found {join_count} JOIN clauses (required: 3)")
        else:
            feedback_parts.append(f"❌ Found only {join_count} JOIN clauses (required: 3)")
        
        # Check 4: GROUP BY clause
        checks['has_group_by'] = "GROUP BY" in content_upper
        if checks['has_group_by']:
            feedback_parts.append("✅ GROUP BY clause present")
        else:
            feedback_parts.append("❌ GROUP BY clause missing")
        
        # Check 5: ORDER BY clause
        checks['has_order_by'] = "ORDER BY" in content_upper
        if checks['has_order_by']:
            feedback_parts.append("✅ ORDER BY clause present")
        else:
            feedback_parts.append("❌ ORDER BY clause missing")
        
        # Check 6: DESC keyword
        checks['has_desc'] = "DESC" in content_upper
        if checks['has_desc']:
            feedback_parts.append("✅ DESC keyword present")
        else:
            feedback_parts.append("❌ DESC keyword missing")
        
        # Check 7: LIMIT clause
        checks['has_limit'] = "LIMIT" in content_upper
        if checks['has_limit']:
            feedback_parts.append("✅ LIMIT clause present")
        else:
            feedback_parts.append("❌ LIMIT clause missing")
        
        # Check 8: Aggregate functions
        has_sum = "SUM(" in content_upper
        has_count = "COUNT(" in content_upper
        checks['has_aggregate'] = has_sum or has_count
        if checks['has_aggregate']:
            agg_funcs = []
            if has_sum:
                agg_funcs.append("SUM")
            if has_count:
                agg_funcs.append("COUNT")
            feedback_parts.append(f"✅ Aggregate functions present: {', '.join(agg_funcs)}")
        else:
            feedback_parts.append("❌ No aggregate functions (SUM/COUNT) found")
        
        # Check 9: Table references
        table_refs = {
            'orders': bool(re.search(r'\borders\b', content, re.IGNORECASE)),
            'products': bool(re.search(r'\bproducts\b', content, re.IGNORECASE)),
            'categories': bool(re.search(r'\bcategories\b', content, re.IGNORECASE)),
            'order_items': bool(re.search(r'\border_items\b', content, re.IGNORECASE)),
        }
        checks['references_tables'] = all(table_refs.values())
        
        if checks['references_tables']:
            feedback_parts.append("✅ All required tables referenced (orders, order_items, products, categories)")
        else:
            missing = [t for t, present in table_refs.items() if not present]
            feedback_parts.append(f"❌ Missing table references: {', '.join(missing)}")
        
        # Check 10: Uppercase keywords (at least SELECT and FROM)
        has_uppercase_select = bool(re.search(r'\bSELECT\b', content))
        has_uppercase_from = bool(re.search(r'\bFROM\b', content))
        checks['uppercase_keywords'] = has_uppercase_select and has_uppercase_from
        
        if checks['uppercase_keywords']:
            feedback_parts.append("✅ SQL keywords in uppercase")
        else:
            feedback_parts.append("❌ SQL keywords not properly capitalized")
        
        # Check 11: Multi-line formatting with indentation
        has_newlines = content.count('\n') >= 8
        has_indentation = bool(re.search(r'\n\s{2,}', content))
        checks['proper_formatting'] = has_newlines and has_indentation
        
        if checks['proper_formatting']:
            feedback_parts.append(f"✅ Proper formatting (multi-line with indentation)")
        else:
            if not has_newlines:
                feedback_parts.append(f"❌ Query should be multi-line (found {content.count('\n')} lines, expected 8+)")
            elif not has_indentation:
                feedback_parts.append("❌ Query lacks proper indentation")
        
        # Check 12: Comments
        has_single_comment = '--' in content
        has_block_comment = '/*' in content and '*/' in content
        checks['has_comment'] = has_single_comment or has_block_comment
        
        if checks['has_comment']:
            comment_type = "single-line (--)" if has_single_comment else "block (/* */)"
            feedback_parts.append(f"✅ Comment present ({comment_type})")
        else:
            feedback_parts.append("❌ No comments found (use -- or /* */)")
        
        # Calculate score
        passed_checks = sum(checks.values())
        total_checks = len(checks)
        score = int((passed_checks / total_checks) * 100)
        
        # Pass threshold: 85% (11/13 checks)
        passed = score >= 85
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "passed_checks": passed_checks,
                "total_checks": total_checks,
                "file_size": len(content),
                "line_count": content.count('\n') + 1,
                "checks": checks
            }
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
