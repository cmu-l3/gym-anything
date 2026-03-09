#!/usr/bin/env python3
"""
Verifier for Document Utility Functions task
"""

import sys
import os
import logging
import tempfile
import re
from typing import Dict, List, Tuple, Any

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_jsdoc_for_function(content: str, func_name: str) -> str:
    """
    Extract JSDoc comment block before a function definition.
    
    Args:
        content: Full file content
        func_name: Name of the function to find JSDoc for
        
    Returns:
        JSDoc comment block or empty string if not found
    """
    # Pattern to match JSDoc comment followed by function
    # Handles export function and regular function
    pattern = r'/\*\*(.*?)\*/\s*(?:export\s+)?function\s+' + re.escape(func_name) + r'\s*[<(]'
    match = re.search(pattern, content, re.DOTALL)
    
    if match:
        return match.group(1)
    return ""


def parse_jsdoc_tags(jsdoc: str) -> Dict[str, List[str]]:
    """
    Parse JSDoc comment into tags.
    
    Returns:
        Dict mapping tag names to list of values
    """
    tags = {
        'description': [],
        'param': [],
        'returns': [],
        'example': []
    }
    
    lines = jsdoc.split('\n')
    current_tag = 'description'
    current_content = []
    
    for line in lines:
        # Remove leading * and whitespace
        line = re.sub(r'^\s*\*\s?', '', line)
        
        # Check if line starts with a tag
        tag_match = re.match(r'@(\w+)\s*(.*)', line)
        
        if tag_match:
            # Save previous tag content
            if current_content:
                tags[current_tag].append(' '.join(current_content).strip())
                current_content = []
            
            # Start new tag
            tag_name = tag_match.group(1).lower()
            tag_content = tag_match.group(2)
            
            if tag_name in ['param', 'params', 'parameter']:
                current_tag = 'param'
            elif tag_name in ['returns', 'return']:
                current_tag = 'returns'
            elif tag_name == 'example':
                current_tag = 'example'
            else:
                current_tag = tag_name
                
            if tag_content:
                current_content.append(tag_content)
        else:
            # Continue previous tag
            if line.strip():
                current_content.append(line.strip())
    
    # Save last tag
    if current_content:
        tags[current_tag].append(' '.join(current_content).strip())
    
    return tags


def validate_param_tags(param_tags: List[str], expected_params: List[str]) -> Tuple[bool, List[str]]:
    """
    Validate that @param tags cover all expected parameters.
    
    Args:
        param_tags: List of @param tag values
        expected_params: List of expected parameter names
        
    Returns:
        (all_found, missing_params)
    """
    found_params = []
    
    for param_tag in param_tags:
        # Extract parameter name from @param tag
        # Format: @param {type} name - description
        # or: @param name - description
        match = re.search(r'(?:\{[^}]+\}\s+)?(\w+)', param_tag)
        if match:
            found_params.append(match.group(1))
    
    missing = [p for p in expected_params if p not in found_params]
    return len(missing) == 0, missing


def verify_documentation(traj, env_info, task_info):
    """
    Verify that utility functions have been properly documented with JSDoc.
    
    Checks for each of the three functions:
    1. JSDoc comment block exists
    2. Description is present and substantive (at least 10 words)
    3. @param tags for all parameters
    4. @returns tag present
    5. @example tag present (for formatCurrency and debounce)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/workspace/utils/helpers.ts"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.ts')
    
    try:
        copy_from_env(container_path, temp_file.name)
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {"passed": False, "score": 0, "feedback": "File not found or empty"}
        
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Define functions to check and their expected parameters
        functions_spec = {
            'formatCurrency': {
                'params': ['amount', 'locale'],
                'needs_example': True,
                'weight': 1.0
            },
            'debounce': {
                'params': ['func', 'wait'],
                'needs_example': True,
                'weight': 1.0
            },
            'deepMerge': {
                'params': ['target', 'source'],
                'needs_example': False,
                'weight': 1.0
            }
        }
        
        total_score = 0.0
        max_score = 0.0
        feedback_parts = []
        function_results = {}
        
        for func_name, spec in functions_spec.items():
            func_score = 0.0
            func_max_score = 5.0  # Max points per function
            func_feedback = []
            
            # Extract JSDoc for this function
            jsdoc = extract_jsdoc_for_function(content, func_name)
            
            if not jsdoc:
                func_feedback.append(f"❌ No JSDoc found for {func_name}")
                function_results[func_name] = {
                    'score': 0,
                    'feedback': ' | '.join(func_feedback)
                }
                max_score += func_max_score
                continue
            
            # Parse JSDoc tags
            tags = parse_jsdoc_tags(jsdoc)
            
            # Check 1: Description exists and is substantive
            description = ' '.join(tags['description'])
            word_count = len(description.split())
            
            if word_count >= 10:
                func_score += 1.0
                func_feedback.append(f"✅ Description present ({word_count} words)")
            elif word_count > 0:
                func_score += 0.5
                func_feedback.append(f"⚠️ Description too brief ({word_count} words, need 10+)")
            else:
                func_feedback.append(f"❌ No description found")
            
            # Check 2: @param tags for all parameters
            expected_params = spec['params']
            param_tags = tags['param']
            
            all_params_found, missing_params = validate_param_tags(param_tags, expected_params)
            
            if all_params_found and len(param_tags) == len(expected_params):
                func_score += 1.5
                func_feedback.append(f"✅ All @param tags present: {', '.join(expected_params)}")
            elif all_params_found:
                func_score += 1.0
                func_feedback.append(f"⚠️ Extra @param tags found")
            else:
                func_score += 0.5 * (len(expected_params) - len(missing_params)) / len(expected_params)
                func_feedback.append(f"❌ Missing @param for: {', '.join(missing_params)}")
            
            # Check 3: @returns tag
            returns_tags = tags['returns']
            
            if returns_tags and len(' '.join(returns_tags).split()) >= 3:
                func_score += 1.0
                func_feedback.append(f"✅ @returns tag present with description")
            elif returns_tags:
                func_score += 0.5
                func_feedback.append(f"⚠️ @returns present but description too brief")
            else:
                func_feedback.append(f"❌ No @returns tag found")
            
            # Check 4: @example tag (if required)
            example_tags = tags['example']
            
            if spec['needs_example']:
                if example_tags and len(' '.join(example_tags)) > 10:
                    func_score += 1.5
                    func_feedback.append(f"✅ @example tag present")
                elif example_tags:
                    func_score += 0.7
                    func_feedback.append(f"⚠️ @example present but incomplete")
                else:
                    func_feedback.append(f"❌ No @example tag found (required)")
            else:
                # Auto-pass for deepMerge
                func_score += 1.5
                func_feedback.append(f"✅ @example not required for {func_name}")
            
            # Store function results
            function_results[func_name] = {
                'score': func_score,
                'max_score': func_max_score,
                'feedback': ' | '.join(func_feedback)
            }
            
            total_score += func_score * spec['weight']
            max_score += func_max_score * spec['weight']
            
            # Add to overall feedback
            feedback_parts.append(f"{func_name}: {' | '.join(func_feedback)}")
        
        # Calculate final score as percentage
        final_score = int((total_score / max_score) * 100) if max_score > 0 else 0
        passed = final_score >= 85
        
        # Build summary feedback
        summary = f"Score: {final_score}% | " + " || ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": summary,
            "details": function_results
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
