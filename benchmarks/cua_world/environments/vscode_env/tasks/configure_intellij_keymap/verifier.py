#!/usr/bin/env python3
"""
Verifier for IntelliJ Keymap Configuration task (configure_intellij_keymap@1)

Checks that IntelliJ-compatible keyboard shortcuts are configured in VSCode.
Two valid approaches:
1. IntelliJ keymap extension installed (automatic full credit)
2. Manual keybindings.json configuration with required mappings
"""

import sys
import os
import logging
import tempfile
import json
from typing import Dict, Any, Tuple, List

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Required IntelliJ -> VSCode command mappings
REQUIRED_MAPPINGS = {
    "ctrl+b": {
        "primary": "editor.action.revealDefinition",
        "alternatives": ["editor.action.goToDeclaration"],
        "description": "Go to Definition"
    },
    "ctrl+alt+b": {
        "primary": "editor.action.goToImplementation",
        "alternatives": ["editor.action.peekImplementation"],
        "description": "Go to Implementation"
    },
    "ctrl+n": {
        "primary": "workbench.action.showAllSymbols",
        "alternatives": ["workbench.action.gotoSymbol"],
        "description": "Go to Symbol in Workspace"
    },
    "ctrl+shift+n": {
        "primary": "workbench.action.quickOpen",
        "alternatives": [],
        "description": "Quick Open File"
    },
    "ctrl+e": {
        "primary": "workbench.action.openRecent",
        "alternatives": ["workbench.action.showEditorsInActiveGroup", "workbench.action.quickOpenRecent"],
        "description": "Recent Files"
    }
}

# Known IntelliJ keymap extension IDs (case-insensitive)
INTELLIJ_KEYMAP_EXTENSIONS = [
    "k--kato.intellij-idea-keybindings",
    "kasecato.vscode-intellij-idea-keybindings",
    "intellij-idea-keybindings"
]


def normalize_key(key: str) -> str:
    """Normalize keyboard shortcut string for comparison"""
    if not key:
        return ""
    # Remove spaces, convert to lowercase
    normalized = key.lower().replace(" ", "").replace("_", "")
    # Normalize modifier order (ctrl, alt, shift)
    parts = normalized.split("+")
    modifiers = []
    keys = []
    
    for part in parts:
        if part in ["ctrl", "control", "cmd", "command"]:
            modifiers.append("ctrl")
        elif part in ["alt", "option"]:
            modifiers.append("alt")
        elif part in ["shift"]:
            modifiers.append("shift")
        else:
            keys.append(part)
    
    # Sort modifiers and combine
    modifiers.sort()
    return "+".join(modifiers + keys)


def copy_file_content(copy_fn, container_path: str) -> str:
    """Helper to copy file from container and read content"""
    temp_file = tempfile.NamedTemporaryFile(mode='w+', delete=False, suffix='.tmp')
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        copy_fn(container_path, temp_path)
        if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
            with open(temp_path, 'r', encoding='utf-8', errors='ignore') as f:
                return f.read()
        return ""
    except Exception as e:
        logger.warning(f"Could not read {container_path}: {e}")
        return ""
    finally:
        if os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def check_extension_installed(extensions_content: str) -> Tuple[bool, str]:
    """
    Check if IntelliJ keymap extension is installed
    
    Returns:
        Tuple of (is_installed, extension_id)
    """
    if not extensions_content:
        return False, ""
    
    lines = extensions_content.strip().split('\n')
    for line in lines:
        line_lower = line.strip().lower()
        for ext_id in INTELLIJ_KEYMAP_EXTENSIONS:
            if ext_id.lower() in line_lower:
                return True, line.strip()
    
    return False, ""


def parse_keybindings(content: str) -> Tuple[bool, List[Dict[str, Any]], str]:
    """
    Parse keybindings.json content
    
    Returns:
        Tuple of (success, keybindings_list, error_message)
    """
    if not content or content.strip() == "":
        return False, [], "Keybindings file is empty"
    
    try:
        data = json.loads(content)
    except json.JSONDecodeError as e:
        return False, [], f"Invalid JSON: {str(e)}"
    
    if not isinstance(data, list):
        return False, [], "Keybindings must be a JSON array"
    
    return True, data, ""


def check_keybinding_mapping(keybindings: List[Dict[str, Any]], 
                             required_key: str, 
                             mapping_info: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check if a specific keybinding is configured correctly
    
    Returns:
        Tuple of (is_configured, matched_command)
    """
    normalized_required = normalize_key(required_key)
    primary_cmd = mapping_info["primary"]
    alternatives = mapping_info["alternatives"]
    
    for binding in keybindings:
        if not isinstance(binding, dict):
            continue
        
        key = binding.get("key", "")
        command = binding.get("command", "")
        
        if not key or not command:
            continue
        
        normalized_key = normalize_key(key)
        
        # Check if this binding matches the required key
        if normalized_key == normalized_required:
            # Check if command matches (primary or alternatives)
            if command == primary_cmd:
                return True, command
            
            if command in alternatives:
                return True, command
            
            # For ctrl+e, accept any command containing "recent"
            if required_key == "ctrl+e" and "recent" in command.lower():
                return True, command
    
    return False, ""


def verify_intellij_keymap(traj, env_info, task_info):
    """
    Main verification function for IntelliJ keymap configuration task.
    
    Approach 1: Check if IntelliJ keymap extension is installed (full credit)
    Approach 2: Check manual keybindings.json configuration (5 required mappings)
    
    Args:
        traj: Trajectory (unused)
        env_info: Environment info with copy_from_env function
        task_info: Task info (unused)
        
    Returns:
        Dict with keys: passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    feedback_parts = []
    
    try:
        # ============================================================
        # APPROACH 1: Check if extension is installed
        # ============================================================
        extensions_content = copy_file_content(
            copy_from_env, 
            "/tmp/keymap_export/extensions.txt"
        )
        
        ext_installed, ext_id = check_extension_installed(extensions_content)
        
        if ext_installed:
            logger.info(f"✅ IntelliJ keymap extension detected: {ext_id}")
            return {
                "passed": True,
                "score": 100,
                "feedback": f"✅ IntelliJ keymap extension installed: {ext_id} | All shortcuts automatically configured"
            }
        
        logger.info("No IntelliJ keymap extension found, checking manual configuration...")
        
        # ============================================================
        # APPROACH 2: Check manual keybindings.json configuration
        # ============================================================
        keybindings_content = copy_file_content(
            copy_from_env,
            "/tmp/keymap_export/keybindings.json"
        )
        
        if not keybindings_content or keybindings_content.strip() in ["", "[]"]:
            feedback_parts.append("❌ Keybindings file is empty or default")
            feedback_parts.append("💡 Suggestion: Install IntelliJ keymap extension OR manually configure keybindings")
            
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Parse keybindings
        parse_success, keybindings, parse_error = parse_keybindings(keybindings_content)
        
        if not parse_success:
            feedback_parts.append(f"❌ Failed to parse keybindings.json: {parse_error}")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Check each required mapping
        configured_count = 0
        missing_mappings = []
        configured_mappings = []
        
        for required_key, mapping_info in REQUIRED_MAPPINGS.items():
            is_configured, matched_cmd = check_keybinding_mapping(
                keybindings, 
                required_key, 
                mapping_info
            )
            
            if is_configured:
                configured_count += 1
                configured_mappings.append(
                    f"{required_key} → {matched_cmd}"
                )
                logger.info(f"✅ Found mapping: {required_key} → {matched_cmd}")
            else:
                missing_mappings.append(
                    f"{required_key} ({mapping_info['description']})"
                )
                logger.info(f"❌ Missing mapping: {required_key}")
        
        # Build feedback
        required_count = len(REQUIRED_MAPPINGS)
        
        if configured_count > 0:
            feedback_parts.append(
                f"Configured {configured_count}/{required_count} shortcuts: {', '.join(configured_mappings[:3])}"
            )
        
        if missing_mappings:
            feedback_parts.append(
                f"❌ Missing: {', '.join(missing_mappings)}"
            )
        
        # Scoring
        score = int((configured_count / required_count) * 100)
        passed = (configured_count >= required_count)
        
        if passed:
            feedback_parts.insert(0, f"✅ All {required_count} IntelliJ shortcuts configured manually")
        else:
            feedback_parts.insert(0, f"❌ Insufficient shortcuts: {configured_count}/{required_count}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }


# Entry point for gym-anything framework
