#!/usr/bin/env python3
"""
Verifier for Error Handling task
"""

import sys
import os
import logging
import tempfile
import ast
from typing import Dict, List, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def analyze_error_handling(source_code: str) -> Dict[str, any]:
    """
    Analyze error handling quality via AST parsing.
    
    Returns dict with:
    - try_blocks: count of try-except blocks
    - specific_exceptions: list of exception types used
    - bare_excepts: count of bare except: clauses (bad practice)
    - has_logging: whether logging is imported
    - logging_calls: count of logging.error/warning/info calls
    - defensive_gets: count of .get() method calls
    - has_context_managers: count of 'with' statements
    """
    try:
        tree = ast.parse(source_code)
    except SyntaxError as e:
        logger.error(f"Syntax error in code: {e}")
        return {
            'parse_error': str(e),
            'try_blocks': 0,
            'specific_exceptions': [],
            'bare_excepts': 0,
            'has_logging': False,
            'logging_calls': 0,
            'defensive_gets': 0,
            'has_context_managers': 0
        }
    
    results = {
        'try_blocks': 0,
        'specific_exceptions': [],
        'bare_excepts': 0,
        'has_logging': False,
        'logging_calls': 0,
        'defensive_gets': 0,
        'has_context_managers': 0,
        'exception_handlers_with_messages': 0
    }
    
    class ErrorHandlingVisitor(ast.NodeVisitor):
        def visit_Try(self, node):
            results['try_blocks'] += 1
            
            for handler in node.handlers:
                if handler.type is None:
                    # Bare except: clause
                    results['bare_excepts'] += 1
                else:
                    # Extract exception type name
                    exc_name = self.get_exception_name(handler.type)
                    if exc_name:
                        results['specific_exceptions'].append(exc_name)
                
                # Check if handler has error messages (not empty)
                if len(handler.body) > 0:
                    has_message = False
                    for stmt in handler.body:
                        if isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Call):
                            has_message = True
                        elif isinstance(stmt, ast.Pass):
                            continue
                        else:
                            has_message = True
                    
                    if has_message:
                        results['exception_handlers_with_messages'] += 1
            
            self.generic_visit(node)
        
        def get_exception_name(self, node):
            """Extract exception type name from AST node"""
            if isinstance(node, ast.Name):
                return node.id
            elif isinstance(node, ast.Attribute):
                # e.g., requests.RequestException
                if isinstance(node.value, ast.Name):
                    return f"{node.value.id}.{node.attr}"
                return node.attr
            elif isinstance(node, ast.Tuple):
                # Multiple exceptions: except (ValueError, TypeError)
                return [self.get_exception_name(elt) for elt in node.elts]
            return None
        
        def visit_Import(self, node):
            for alias in node.names:
                if 'logging' in alias.name:
                    results['has_logging'] = True
            self.generic_visit(node)
        
        def visit_ImportFrom(self, node):
            if node.module and 'logging' in node.module:
                results['has_logging'] = True
            self.generic_visit(node)
        
        def visit_Call(self, node):
            # Check for logging calls
            if isinstance(node.func, ast.Attribute):
                if node.func.attr in ['error', 'warning', 'info', 'debug', 'critical']:
                    # Check if it's logging.error() or logger.error()
                    if isinstance(node.func.value, ast.Name):
                        if node.func.value.id in ['logging', 'logger', 'log']:
                            results['logging_calls'] += 1
                
                # Check for defensive .get() usage
                if node.func.attr == 'get':
                    results['defensive_gets'] += 1
            
            self.generic_visit(node)
        
        def visit_With(self, node):
            results['has_context_managers'] += 1
            self.generic_visit(node)
    
    visitor = ErrorHandlingVisitor()
    visitor.visit(tree)
    
    return results


def check_required_exceptions(exceptions: List[str]) -> Tuple[int, List[str]]:
    """
    Check if required exception types are present.
    
    Returns (count_found, list_of_found_types)
    """
    # Flatten list in case of nested lists
    flat_exceptions = []
    for exc in exceptions:
        if isinstance(exc, list):
            flat_exceptions.extend(exc)
        else:
            flat_exceptions.append(exc)
    
    # Convert to lowercase for case-insensitive matching
    exc_lower = [str(e).lower() for e in flat_exceptions]
    
    required_categories = {
        'network': ['requestexception', 'connectionerror', 'timeout', 'httperror'],
        'file': ['filenotfounderror', 'ioerror', 'permissionerror', 'oserror'],
        'json': ['jsondecodeerror', 'valueerror'],
        'data': ['keyerror', 'typeerror', 'attributeerror']
    }
    
    found_categories = []
    found_count = 0
    
    for category, exception_keywords in required_categories.items():
        for exc in exc_lower:
            if any(keyword in exc for keyword in exception_keywords):
                found_categories.append(category)
                found_count += 1
                break
    
    return found_count, found_categories


def verify_error_handling(traj, env_info, task_info):
    """
    Main verification function for error handling task.
    
    Checks:
    1. Multiple try-except blocks present (at least 3)
    2. Specific exception types used (not bare except:)
    3. Required exceptions covered (network, file, json)
    4. Logging framework imported and used
    5. Defensive programming patterns (dict.get)
    6. Error messages present in handlers
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/workspace/data_pipeline/fetch_data.py"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.py', mode='w+')
    
    try:
        # Copy modified script from container
        copy_from_env(container_path, temp_file.name)
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ File not found or empty: {container_path}"
            }
        
        # Read source code
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            source_code = f.read()
        
        # Analyze error handling
        analysis = analyze_error_handling(source_code)
        
        if 'parse_error' in analysis:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Syntax error in code: {analysis['parse_error']}"
            }
        
        # Scoring criteria
        score = 0
        feedback_parts = []
        
        # Criterion 1: Multiple try-except blocks (0-25 points)
        try_blocks = analysis['try_blocks']
        if try_blocks >= 3:
            score += 25
            feedback_parts.append(f"✅ Multiple try-except blocks added ({try_blocks} blocks)")
        elif try_blocks >= 2:
            score += 15
            feedback_parts.append(f"⚠️ Some try-except blocks added ({try_blocks}), but coverage incomplete")
        elif try_blocks >= 1:
            score += 8
            feedback_parts.append(f"⚠️ Only {try_blocks} try-except block found")
        else:
            feedback_parts.append("❌ No try-except blocks found")
        
        # Criterion 2: Specific exception types (0-25 points)
        exception_count, found_categories = check_required_exceptions(analysis['specific_exceptions'])
        
        if exception_count >= 3:
            score += 25
            feedback_parts.append(f"✅ Specific exception types used ({exception_count} categories: {', '.join(found_categories)})")
        elif exception_count >= 2:
            score += 15
            feedback_parts.append(f"⚠️ Some specific exceptions ({exception_count} categories), but missing key types")
        elif exception_count >= 1:
            score += 8
            feedback_parts.append(f"⚠️ Limited exception coverage ({exception_count} category)")
        else:
            if len(analysis['specific_exceptions']) > 0:
                feedback_parts.append(f"⚠️ Generic exceptions used: {', '.join(str(e) for e in analysis['specific_exceptions'][:3])}")
            else:
                feedback_parts.append("❌ No specific exception types found")
        
        # Penalty for bare except clauses
        if analysis['bare_excepts'] > 0:
            score -= 10
            feedback_parts.append(f"⚠️ Found {analysis['bare_excepts']} bare 'except:' clauses (anti-pattern, -10 pts)")
        
        # Criterion 3: Logging framework (0-20 points)
        if analysis['has_logging'] and analysis['logging_calls'] >= 2:
            score += 20
            feedback_parts.append(f"✅ Logging properly instrumented ({analysis['logging_calls']} logging calls)")
        elif analysis['has_logging']:
            score += 10
            feedback_parts.append(f"⚠️ Logging imported but underutilized ({analysis['logging_calls']} calls)")
        else:
            feedback_parts.append("❌ No logging framework used")
        
        # Criterion 4: Defensive programming (0-10 points)
        if analysis['defensive_gets'] >= 2:
            score += 10
            feedback_parts.append(f"✅ Defensive dictionary access ({analysis['defensive_gets']} .get() calls)")
        elif analysis['defensive_gets'] >= 1:
            score += 5
            feedback_parts.append(f"⚠️ Some defensive patterns ({analysis['defensive_gets']} .get() call)")
        
        # Criterion 5: Error messages in handlers (0-20 points)
        if analysis['exception_handlers_with_messages'] >= 3:
            score += 20
            feedback_parts.append(f"✅ Error handlers contain messages ({analysis['exception_handlers_with_messages']} handlers)")
        elif analysis['exception_handlers_with_messages'] >= 2:
            score += 12
            feedback_parts.append(f"⚠️ Some error messages present ({analysis['exception_handlers_with_messages']} handlers)")
        elif analysis['exception_handlers_with_messages'] >= 1:
            score += 6
            feedback_parts.append(f"⚠️ Limited error messages ({analysis['exception_handlers_with_messages']} handler)")
        else:
            feedback_parts.append("❌ No error messages in exception handlers")
        
        # Normalize score (max 100)
        score = max(0, min(100, score))
        
        # Determine pass/fail (threshold: 75%)
        passed = score >= 75
        
        # Build detailed feedback
        feedback = " | ".join(feedback_parts)
        feedback += f"\n\n📊 Analysis Summary:"
        feedback += f"\n  • Try-except blocks: {try_blocks}"
        feedback += f"\n  • Specific exceptions: {len(analysis['specific_exceptions'])} types"
        feedback += f"\n  • Exception categories: {', '.join(found_categories) if found_categories else 'none'}"
        feedback += f"\n  • Bare excepts: {analysis['bare_excepts']}"
        feedback += f"\n  • Logging: {'Yes' if analysis['has_logging'] else 'No'} ({analysis['logging_calls']} calls)"
        feedback += f"\n  • Defensive .get(): {analysis['defensive_gets']}"
        feedback += f"\n  • Final Score: {score}/100"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp file
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
