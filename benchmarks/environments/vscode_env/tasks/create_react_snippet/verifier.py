#!/usr/bin/env python3
"""
Verifier for Create React Snippet task
Checks if a valid React component snippet was created with correct structure
"""

import sys
import os
import json
import logging
import tempfile
import shutil
from pathlib import Path
from typing import Dict, Any, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_snippet_created(traj, env_info, task_info):
    """
    Verify that a React functional component snippet was created correctly.
    
    Checks for:
    1. Snippet file exists at correct location (0.1 pts)
    2. Valid JSON syntax (0.1 pts)
    3. Has snippet definition (0.1 pts)
    4. Correct prefix 'rfc' (1.0 pts)
    5. Has description (0.5 pts)
    6. Body is valid array (0.5 pts)
    7. Contains TypeScript interface/type (1.0 pts)
    8. Contains functional component declaration (1.5 pts)
    9. Contains useState hook (1.5 pts)
    10. Contains return statement with JSX (1.0 pts)
    11. Contains export default (1.0 pts)
    
    Total: 8.0 points, normalized to [0.0, 1.0]
    Success threshold: >= 0.95 (7.6/8.0 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    info = {
        "success": False,
        "file_exists": False,
        "valid_json": False,
        "has_snippet": False,
        "correct_prefix": False,
        "has_description": False,
        "body_structure": False,
        "contains_interface": False,
        "contains_component": False,
        "contains_usestate": False,
        "contains_return": False,
        "contains_export": False,
        "errors": []
    }
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_snippet_verify_')
    
    try:
        # Check all possible locations for React snippets
        possible_paths = [
            "/home/ga/.config/Code/User/snippets/typescriptreact.json",
            "/home/ga/.config/Code/User/snippets/javascriptreact.json",
            "/home/ga/.config/Code/User/snippets/typescript.json",
            "/home/ga/.config/Code/User/snippets/javascript.json",
            "/home/ga/.config/Code/User/snippets/react.json"
        ]
        
        snippet_data = None
        found_path = None
        
        for snippet_path in possible_paths:
            try:
                temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', dir=temp_dir)
                
                try:
                    copy_from_env(snippet_path, temp_file.name)
                    
                    if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                        info["file_exists"] = True
                        found_path = snippet_path
                        
                        with open(temp_file.name, 'r', encoding='utf-8') as f:
                            content = f.read()
                            # Try to parse JSON
                            snippet_data = json.loads(content)
                            info["valid_json"] = True
                        
                        logger.info(f"Found valid snippet file at {snippet_path}")
                        break  # Found valid file
                        
                except json.JSONDecodeError as e:
                    info["errors"].append(f"Invalid JSON in {snippet_path}: {str(e)[:100]}")
                    logger.debug(f"JSON decode error in {snippet_path}: {e}")
                except Exception as e:
                    logger.debug(f"Could not read {snippet_path}: {e}")
                finally:
                    if os.path.exists(temp_file.name):
                        os.unlink(temp_file.name)
                        
            except Exception as e:
                logger.debug(f"Error accessing {snippet_path}: {e}")
        
        if not info["file_exists"]:
            info["errors"].append("No React snippet file found in expected locations")
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No snippet file created at expected location (/home/ga/.config/Code/User/snippets/)"
            }
        
        if not info["valid_json"]:
            info["errors"].append("Snippet file exists but contains invalid JSON")
            return {
                "passed": False,
                "score": 10,
                "feedback": f"❌ Snippet file has invalid JSON syntax: {info['errors'][-1]}"
            }
        
        # Check if snippet data is empty
        if not snippet_data or len(snippet_data) == 0:
            info["errors"].append("Snippet file is empty (no snippet definitions)")
            return {
                "passed": False,
                "score": 20,
                "feedback": "❌ Snippet file exists but is empty"
            }
        
        info["has_snippet"] = True
        
        # Look for snippet with prefix 'rfc'
        snippet_found = False
        snippet_name_used = None
        
        for snippet_name, snippet_def in snippet_data.items():
            if not isinstance(snippet_def, dict):
                logger.debug(f"Skipping non-dict snippet: {snippet_name}")
                continue
            
            # Check for required fields
            prefix = snippet_def.get("prefix", "")
            description = snippet_def.get("description", "")
            body = snippet_def.get("body", [])
            
            # Check if this snippet has prefix 'rfc'
            is_rfc_prefix = False
            if prefix == "rfc":
                is_rfc_prefix = True
            elif isinstance(prefix, list) and "rfc" in prefix:
                is_rfc_prefix = True
            
            if is_rfc_prefix:
                info["correct_prefix"] = True
                snippet_found = True
                snippet_name_used = snippet_name
                
                # Check description
                if description and len(description) > 0:
                    info["has_description"] = True
                
                # Check body structure
                if isinstance(body, list) and len(body) > 0:
                    info["body_structure"] = True
                    
                    # Join body into single string for content analysis
                    body_text = "\n".join(str(line) for line in body)
                    body_lower = body_text.lower()
                    
                    # Check for TypeScript interface or type
                    if "interface" in body_lower or ("type" in body_lower and "=" in body_text):
                        info["contains_interface"] = True
                    
                    # Check for functional component declaration
                    # Looking for patterns like: const X = () => or const X: React.FC
                    if ("const" in body_lower and "=>" in body_text) or ("function" in body_lower):
                        # Also check for React.FC or similar
                        if "react.fc" in body_lower or "fc<" in body_lower or ("=>" in body_text and "const" in body_lower):
                            info["contains_component"] = True
                    
                    # Check for useState hook
                    if "usestate" in body_lower:
                        info["contains_usestate"] = True
                    
                    # Check for return statement with JSX
                    if "return" in body_lower:
                        # Look for JSX indicators
                        if ("<" in body_text and ">" in body_text) or "jsx" in body_lower or "<div" in body_lower or "<h1" in body_lower:
                            info["contains_return"] = True
                    
                    # Check for export default
                    if "export" in body_lower and "default" in body_lower:
                        info["contains_export"] = True
                
                break  # Found the rfc snippet, stop searching
        
        if not snippet_found:
            info["errors"].append("No snippet with prefix 'rfc' found")
            return {
                "passed": False,
                "score": 30,
                "feedback": "❌ Snippet file exists but no snippet with prefix 'rfc' found"
            }
        
        # Calculate score with partial credit
        points = 0.0
        max_points = 8.0
        feedback_parts = []
        
        # File existence (already confirmed)
        points += 0.1
        
        # Valid JSON (already confirmed)
        points += 0.1
        
        # Has snippet (already confirmed)
        points += 0.1
        
        # Correct prefix
        if info["correct_prefix"]:
            points += 1.0
            feedback_parts.append("✅ Correct prefix 'rfc'")
        else:
            info["errors"].append("Snippet prefix is not 'rfc'")
            feedback_parts.append("❌ Incorrect prefix")
        
        # Has description
        if info["has_description"]:
            points += 0.5
            feedback_parts.append("✅ Description present")
        else:
            info["errors"].append("Snippet is missing description")
            feedback_parts.append("❌ Missing description")
        
        # Body structure
        if info["body_structure"]:
            points += 0.5
            feedback_parts.append("✅ Valid body array")
        else:
            info["errors"].append("Snippet body is not a valid array")
            feedback_parts.append("❌ Invalid body structure")
        
        # Contains interface
        if info["contains_interface"]:
            points += 1.0
            feedback_parts.append("✅ TypeScript interface/type found")
        else:
            info["errors"].append("Snippet body missing TypeScript interface/type definition")
            feedback_parts.append("❌ Missing interface/type")
        
        # Contains component
        if info["contains_component"]:
            points += 1.5
            feedback_parts.append("✅ Functional component declaration found")
        else:
            info["errors"].append("Snippet body missing functional component declaration")
            feedback_parts.append("❌ Missing component declaration")
        
        # Contains useState
        if info["contains_usestate"]:
            points += 1.5
            feedback_parts.append("✅ useState hook found")
        else:
            info["errors"].append("Snippet body missing useState hook")
            feedback_parts.append("❌ Missing useState hook")
        
        # Contains return
        if info["contains_return"]:
            points += 1.0
            feedback_parts.append("✅ JSX return statement found")
        else:
            info["errors"].append("Snippet body missing return statement with JSX")
            feedback_parts.append("❌ Missing return/JSX")
        
        # Contains export
        if info["contains_export"]:
            points += 1.0
            feedback_parts.append("✅ Export default found")
        else:
            info["errors"].append("Snippet body missing export default")
            feedback_parts.append("❌ Missing export default")
        
        # Calculate final score
        score = int((points / max_points) * 100)
        
        # Success threshold: >= 95% (7.6/8.0 points)
        if points >= 7.6:
            info["success"] = True
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification result: {points}/{max_points} points ({score}/100) - Success: {info['success']}")
        if info["errors"]:
            logger.info(f"Errors: {info['errors']}")
        
        return {
            "passed": info["success"],
            "score": score,
            "feedback": feedback,
            "details": info
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
