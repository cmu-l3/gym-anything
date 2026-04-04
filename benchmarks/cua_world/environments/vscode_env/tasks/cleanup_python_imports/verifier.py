#!/usr/bin/env python3
"""
Verifier for cleanup_python_imports@1
Checks that unused imports are removed and remaining imports are properly organized
"""

import sys
import os
import ast
import logging
import tempfile
from typing import List, Tuple, Dict, Set

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_import_names(file_path: str) -> Set[str]:
    """
    Extract all imported names from a Python file.
    Returns a set of all names that were imported.
    """
    with open(file_path, 'r') as f:
        try:
            tree = ast.parse(f.read())
        except SyntaxError:
            return set()
    
    imported_names = set()
    
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                # Add the imported name or its alias
                name = alias.asname if alias.asname else alias.name
                imported_names.add(name)
                # Also add the base module name
                imported_names.add(alias.name.split('.')[0])
        
        elif isinstance(node, ast.ImportFrom):
            for alias in node.names:
                # Add the imported name or its alias
                name = alias.asname if alias.asname else alias.name
                imported_names.add(name)
    
    return imported_names


def extract_used_names(file_path: str) -> Set[str]:
    """
    Extract all names used in the file (variables, function calls, etc.)
    excluding import statements.
    """
    with open(file_path, 'r') as f:
        try:
            tree = ast.parse(f.read())
        except SyntaxError:
            return set()
    
    used_names = set()
    
    class NameVisitor(ast.NodeVisitor):
        def __init__(self):
            self.in_import = False
            
        def visit_Import(self, node):
            # Skip import statements
            pass
            
        def visit_ImportFrom(self, node):
            # Skip import statements
            pass
        
        def visit_Name(self, node):
            if not self.in_import:
                used_names.add(node.id)
            self.generic_visit(node)
        
        def visit_Attribute(self, node):
            # Get the base name (e.g., 'pd' from 'pd.read_csv')
            if isinstance(node.value, ast.Name):
                used_names.add(node.value.id)
            self.generic_visit(node)
    
    visitor = NameVisitor()
    visitor.visit(tree)
    
    return used_names


def get_import_lines_with_positions(file_path: str) -> List[Tuple[int, str]]:
    """
    Get all import lines with their line numbers.
    Returns list of (line_number, import_line) tuples.
    """
    with open(file_path, 'r') as f:
        lines = f.readlines()
    
    import_lines = []
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith('import ') or stripped.startswith('from '):
            import_lines.append((i, stripped))
    
    return import_lines


def check_import_organization(file_path: str) -> Tuple[bool, str]:
    """
    Check if imports are organized according to PEP 8:
    1. Standard library
    2. Third-party
    3. Local
    
    Returns (is_organized, feedback_message)
    """
    import_lines = get_import_lines_with_positions(file_path)
    
    if not import_lines:
        return True, "No imports found"
    
    # Categorize imports by their position
    local_import_positions = []
    other_import_positions = []
    
    for line_num, line in import_lines:
        # Local imports start with "from ." or "from myproject"
        if line.startswith('from .') or line.startswith('from myproject'):
            local_import_positions.append(line_num)
        else:
            other_import_positions.append(line_num)
    
    # Check: local imports should come after other imports
    if local_import_positions and other_import_positions:
        if min(local_import_positions) < max(other_import_positions):
            return False, "Local imports appear before standard/third-party imports"
    
    return True, "Imports are properly organized"


def verify_import_cleanup(traj, env_info, task_info):
    """
    Verify that imports are cleaned up and organized properly.
    
    Checks:
    1. Unused imports are removed (40% weight)
    2. Used imports are preserved (40% weight)
    3. Imports are organized (20% weight)
    4. No syntax errors (must pass)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    result_path = "/tmp/cleanup_imports_result/data_processor.py"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.py', mode='w')
    
    try:
        # Copy file from container
        try:
            copy_from_env(result_path, temp_file.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy file: {str(e)}"}
        
        if not os.path.exists(temp_file.name):
            return {"passed": False, "score": 0, "feedback": "File not found: data_processor.py"}
        
        # Read content
        with open(temp_file.name, 'r') as f:
            content = f.read()
        
        # Check 0: Syntax validity (must pass)
        try:
            ast.parse(content)
        except SyntaxError as e:
            return {"passed": False, "score": 0, "feedback": f"Syntax error in modified file: {e}"}
        
        # Extract imported and used names
        imported_names = extract_import_names(temp_file.name)
        used_names = extract_used_names(temp_file.name)
        
        # Also check raw content for specific patterns
        content_lower = content.lower()
        
        feedback_parts = []
        reward = 0.0
        
        # Check 1: Unused imports should be removed (40% weight)
        # These imports are NOT used in the code
        SHOULD_BE_REMOVED = {
            'sys': 'sys',
            'requests': 'requests',
            'matplotlib': 'matplotlib',
            'plt': 'matplotlib.pyplot',
            'defaultdict': 'defaultdict',
            're': 're',
            'yaml': 'yaml',
            'csv': 'csv',
            'time': 'time'
        }
        
        remaining_unused = []
        for name, pattern in SHOULD_BE_REMOVED.items():
            # Check if import statement is still present
            if f'import {pattern}' in content or f'import {name}' in content:
                remaining_unused.append(name)
            elif imported_names and name in imported_names:
                remaining_unused.append(name)
        
        # Special check for DATABASE_URL from config
        if 'DATABASE_URL' in content or 'database_url' in content_lower:
            # Check if it's in an import or actually used
            if 'from .config import' in content or 'from myproject.config import' in content:
                # Check if DATABASE_URL is actually used outside imports
                lines = content.split('\n')
                non_import_lines = [l for l in lines if not (l.strip().startswith('import ') or l.strip().startswith('from '))]
                non_import_content = '\n'.join(non_import_lines)
                if 'DATABASE_URL' not in non_import_content:
                    remaining_unused.append('DATABASE_URL')
        
        unused_removal_score = max(0, 0.4 - len(remaining_unused) * 0.05)
        reward += unused_removal_score
        
        if len(remaining_unused) == 0:
            feedback_parts.append("✅ All unused imports removed")
        else:
            feedback_parts.append(f"❌ Still has unused imports: {', '.join(remaining_unused[:5])}")
        
        # Check 2: Used imports should be preserved (40% weight)
        # These imports ARE used in the code
        MUST_BE_PRESENT = {
            'json': ['import json', 'json.load'],
            'Dict': ['from typing import', 'Dict'],
            'pd': ['import pandas as pd', 'pd.read_csv'],
            'np': ['import numpy as np', 'np.mean'],
            'datetime': ['from datetime import datetime', 'datetime.now'],
            'Path': ['from pathlib import Path', 'Path('],
            'logging': ['import logging', 'logging.error'],
            'validate_data': ['from .utils import validate_data', 'validate_data('],
            'format_output': ['from .utils import', 'format_output(']
        }
        
        missing_used = []
        for name, patterns in MUST_BE_PRESENT.items():
            found = False
            for pattern in patterns:
                if pattern.lower() in content_lower:
                    found = True
                    break
            if not found:
                missing_used.append(name)
        
        used_preservation_score = max(0, 0.4 - len(missing_used) * 0.08)
        reward += used_preservation_score
        
        if len(missing_used) == 0:
            feedback_parts.append("✅ All necessary imports preserved")
        else:
            feedback_parts.append(f"❌ Missing necessary imports: {', '.join(missing_used[:5])}")
        
        # Check 3: Import organization (20% weight)
        is_organized, org_message = check_import_organization(temp_file.name)
        
        if is_organized:
            reward += 0.2
            feedback_parts.append(f"✅ {org_message}")
        else:
            feedback_parts.append(f"❌ {org_message}")
        
        # Success threshold
        passed = reward >= 0.8
        score = int(reward * 100)
        
        feedback = " | ".join(feedback_parts)
        
        metadata = {
            "passed": passed,
            "score": score,
            "reward": reward,
            "remaining_unused_imports": remaining_unused,
            "missing_used_imports": missing_used,
            "is_organized": is_organized,
            "feedback": feedback
        }
        
        return metadata
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
