#!/usr/bin/env python3
"""
Verifier for Add Type Hints task
Uses AST parsing to validate type annotations
"""

import sys
import os
import logging
import tempfile
import ast
from typing import Dict, List, Set, Any

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_typing_imports(tree: ast.Module) -> Set[str]:
    """Extract typing imports from AST"""
    imports = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            if node.module == 'typing':
                for alias in node.names:
                    name = alias.name if isinstance(alias.name, str) else str(alias.name)
                    if name != '*':  # Ignore star imports
                        imports.add(name)
    return imports


def analyze_function_annotations(tree: ast.Module) -> Dict[str, Dict[str, Any]]:
    """Analyze type annotations for all functions"""
    functions = {}
    
    for node in tree.body:
        if isinstance(node, ast.FunctionDef):
            func_info = {
                'params': [],
                'param_annotations': {},
                'param_annotations_count': 0,
                'return_annotation': None,
                'return_annotation_str': ''
            }
            
            # Analyze parameters
            for arg in node.args.args:
                param_name = arg.arg
                func_info['params'].append(param_name)
                
                if arg.annotation:
                    try:
                        annotation_str = ast.unparse(arg.annotation)
                        func_info['param_annotations'][param_name] = annotation_str
                        func_info['param_annotations_count'] += 1
                    except Exception as e:
                        logger.warning(f"Failed to unparse annotation for {param_name}: {e}")
            
            # Analyze return type
            if node.returns:
                try:
                    func_info['return_annotation'] = node.returns
                    func_info['return_annotation_str'] = ast.unparse(node.returns)
                except Exception as e:
                    logger.warning(f"Failed to unparse return annotation: {e}")
            
            functions[node.name] = func_info
    
    return functions


def verify_type_hints(traj, env_info, task_info):
    """
    Verify that type hints were added correctly.
    
    Checks:
    1. Typing imports present (20%): from typing import List, Dict, Optional, Any
    2. All 5 functions fully annotated (30%): all params + return type
    3. Optional types correct (25%): calculate_average return, merge_configs param, process_records param
    4. Collection generics used (25%): List[T], Dict[K,V] instead of bare list/dict
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple file locations
    container_paths = [
        "/tmp/data_processor_result.py",
        "/home/ga/workspace/type_hints_project/data_processor.py"
    ]
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    file_found = False
    
    try:
        for container_path in container_paths:
            try:
                copy_from_env(container_path, temp_file.name)
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    file_found = True
                    logger.info(f"Found file at: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not file_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": "File not found at expected locations"
            }
        
        # Read and parse file
        content = read_file_content(temp_file.name)
        if not content:
            return {"passed": False, "score": 0, "feedback": "File is empty"}
        
        # Parse AST
        try:
            tree = ast.parse(content)
        except SyntaxError as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Python syntax error: {e}"
            }
        
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        
        # Criterion 1: Typing imports present (20%)
        imports = parse_typing_imports(tree)
        required_imports = {'List', 'Dict', 'Optional', 'Any'}
        has_all_imports = required_imports.issubset(imports)
        
        import_score = 0
        if has_all_imports:
            criteria_passed += 1
            import_score = 20
            feedback_parts.append(f"✅ Typing imports present: {', '.join(sorted(imports))}")
        else:
            missing = required_imports - imports
            feedback_parts.append(f"❌ Missing typing imports: {', '.join(missing)}")
        
        # Criterion 2: All functions fully annotated (30%)
        functions = analyze_function_annotations(tree)
        expected_functions = [
            'calculate_average',
            'format_user_data',
            'filter_by_threshold',
            'merge_configs',
            'process_records'
        ]
        
        all_annotated = True
        annotation_issues = []
        
        for func_name in expected_functions:
            if func_name not in functions:
                all_annotated = False
                annotation_issues.append(f"{func_name} not found")
                continue
            
            func = functions[func_name]
            param_count = len(func['params'])
            annotated_count = func['param_annotations_count']
            
            # Check all params have annotations
            if annotated_count < param_count:
                all_annotated = False
                missing_params = [p for p in func['params'] if p not in func['param_annotations']]
                annotation_issues.append(f"{func_name}: missing param annotations for {missing_params}")
            
            # Check return annotation exists
            if not func['return_annotation_str']:
                all_annotated = False
                annotation_issues.append(f"{func_name}: missing return annotation")
        
        annotation_score = 0
        if all_annotated:
            criteria_passed += 1
            annotation_score = 30
            feedback_parts.append("✅ All 5 functions fully annotated")
        else:
            feedback_parts.append(f"❌ Annotation issues: {'; '.join(annotation_issues[:3])}")
        
        # Criterion 3: Optional types correct (25%)
        optional_correct = True
        optional_issues = []
        
        # Check calculate_average return type has Optional
        if 'calculate_average' in functions:
            ret = functions['calculate_average']['return_annotation_str']
            if 'Optional' not in ret and 'Union' not in ret:
                optional_correct = False
                optional_issues.append("calculate_average return should be Optional[float]")
        
        # Check merge_configs has Optional for override_config
        if 'merge_configs' in functions:
            params = functions['merge_configs']['param_annotations']
            override_param = params.get('override_config', '')
            if 'Optional' not in override_param and 'Union' not in override_param:
                optional_correct = False
                optional_issues.append("merge_configs override_config should be Optional")
        
        # Check process_records has Optional for max_results
        if 'process_records' in functions:
            params = functions['process_records']['param_annotations']
            max_param = params.get('max_results', '')
            if 'Optional' not in max_param and 'Union' not in max_param:
                optional_correct = False
                optional_issues.append("process_records max_results should be Optional")
        
        optional_score = 0
        if optional_correct:
            criteria_passed += 1
            optional_score = 25
            feedback_parts.append("✅ Optional types used correctly")
        else:
            feedback_parts.append(f"❌ Optional issues: {'; '.join(optional_issues)}")
        
        # Criterion 4: Collection generics used (25%)
        generics_used = True
        generic_issues = []
        
        for func_name, func in functions.items():
            # Check parameters
            for param_name, annotation in func['param_annotations'].items():
                # Check if bare list/dict used
                if annotation.lower() in ['list', 'dict']:
                    generics_used = False
                    generic_issues.append(f"{func_name}.{param_name} uses bare '{annotation}'")
                # Check if List or Dict without brackets (should have generics)
                elif annotation in ['List', 'Dict']:
                    generics_used = False
                    generic_issues.append(f"{func_name}.{param_name} uses {annotation} without type parameters")
            
            # Check return type
            ret = func['return_annotation_str']
            if ret.lower() in ['list', 'dict']:
                generics_used = False
                generic_issues.append(f"{func_name} return uses bare '{ret}'")
            elif ret in ['List', 'Dict']:
                generics_used = False
                generic_issues.append(f"{func_name} return uses {ret} without type parameters")
        
        generics_score = 0
        if generics_used:
            criteria_passed += 1
            generics_score = 25
            feedback_parts.append("✅ Collection generics used properly")
        else:
            feedback_parts.append(f"❌ Generic issues: {'; '.join(generic_issues[:3])}")
        
        # Calculate total score
        total_score = import_score + annotation_score + optional_score + generics_score
        passed = total_score >= 80
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": total_score,
            "feedback": feedback,
            "details": {
                "imports_found": list(imports),
                "functions_analyzed": list(functions.keys()),
                "criteria_passed": criteria_passed,
                "import_score": import_score,
                "annotation_score": annotation_score,
                "optional_score": optional_score,
                "generics_score": generics_score
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
