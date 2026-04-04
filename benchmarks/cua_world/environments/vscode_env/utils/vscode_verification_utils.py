#!/usr/bin/env python3
"""
VSCode verification utilities for gym-anything tasks
Provides helper functions to verify VSCode tasks using configuration parsing and file inspection
"""

import json
import logging
import os
import tempfile
import shutil
import subprocess
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional, Callable

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_vscode_settings(filepath: str) -> Dict[str, Any]:
    """
    Parse VSCode settings.json file
    
    Args:
        filepath: Path to settings.json
        
    Returns:
        Dict containing parsed settings
    """
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Error parsing settings.json: {e}")
        return {}


def parse_launch_json(filepath: str) -> Dict[str, Any]:
    """
    Parse VSCode launch.json debug configuration
    
    Args:
        filepath: Path to launch.json
        
    Returns:
        Dict containing parsed launch configuration
    """
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Error parsing launch.json: {e}")
        return {}


def get_installed_extensions(extensions_dir: str) -> List[str]:
    """
    Get list of installed VSCode extensions
    
    Args:
        extensions_dir: Path to extensions directory
        
    Returns:
        List of extension IDs
    """
    try:
        if not os.path.exists(extensions_dir):
            return []
        
        extensions = []
        for item in os.listdir(extensions_dir):
            item_path = os.path.join(extensions_dir, item)
            if os.path.isdir(item_path):
                # Extension folder format: publisher.name-version
                # Extract publisher.name part
                if '-' in item:
                    ext_id = item.rsplit('-', 1)[0]
                    extensions.append(ext_id)
        
        return extensions
    except Exception as e:
        logger.error(f"Error getting installed extensions: {e}")
        return []


def check_extension_installed(extensions: List[str], extension_id: str) -> bool:
    """
    Check if a specific extension is installed
    
    Args:
        extensions: List of installed extension IDs
        extension_id: Extension ID to check (e.g., "ms-python.python")
        
    Returns:
        True if extension is installed, False otherwise
    """
    return extension_id.lower() in [ext.lower() for ext in extensions]


def get_git_commits(repo_path: str, max_count: int = 10) -> List[Dict[str, str]]:
    """
    Get Git commit history
    
    Args:
        repo_path: Path to Git repository
        max_count: Maximum number of commits to retrieve
        
    Returns:
        List of commit dicts with 'hash', 'message', 'author', 'date'
    """
    try:
        result = subprocess.run(
            ['git', '-C', repo_path, 'log', f'-{max_count}', '--format=%H|%s|%an|%ad'],
            capture_output=True,
            text=True,
            check=True
        )
        
        commits = []
        for line in result.stdout.strip().split('\n'):
            if line:
                parts = line.split('|', 3)
                if len(parts) == 4:
                    commits.append({
                        'hash': parts[0],
                        'message': parts[1],
                        'author': parts[2],
                        'date': parts[3]
                    })
        
        return commits
    except Exception as e:
        logger.error(f"Error getting Git commits: {e}")
        return []


def get_git_status(repo_path: str) -> Dict[str, Any]:
    """
    Get Git repository status
    
    Args:
        repo_path: Path to Git repository
        
    Returns:
        Dict with 'staged', 'unstaged', 'untracked' file lists
    """
    try:
        result = subprocess.run(
            ['git', '-C', repo_path, 'status', '--porcelain'],
            capture_output=True,
            text=True,
            check=True
        )
        
        status = {
            'staged': [],
            'unstaged': [],
            'untracked': []
        }
        
        for line in result.stdout.strip().split('\n'):
            if line:
                status_code = line[:2]
                filename = line[3:]
                
                if status_code[0] in ['M', 'A', 'D', 'R', 'C']:
                    status['staged'].append(filename)
                if status_code[1] in ['M', 'D']:
                    status['unstaged'].append(filename)
                if status_code == '??':
                    status['untracked'].append(filename)
        
        return status
    except Exception as e:
        logger.error(f"Error getting Git status: {e}")
        return {'staged': [], 'unstaged': [], 'untracked': []}


def read_file_content(filepath: str) -> str:
    """
    Read file content
    
    Args:
        filepath: Path to file
        
    Returns:
        File content as string
    """
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            return f.read()
    except Exception as e:
        logger.error(f"Error reading file {filepath}: {e}")
        return ""


def check_file_exists(filepath: str) -> bool:
    """
    Check if file exists
    
    Args:
        filepath: Path to file
        
    Returns:
        True if file exists, False otherwise
    """
    return os.path.exists(filepath)


def copy_and_parse_json(container_path: str, copy_from_env_fn: Callable) -> Tuple[bool, Dict[str, Any], str]:
    """
    Copy JSON file from container and parse it
    
    Args:
        container_path: Path to JSON file in container
        copy_from_env_fn: Function to copy files from container
        
    Returns:
        Tuple of (success, parsed_data, error_message)
    """
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env_fn(container_path, temp_file.name)
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return False, {}, f"File not found or empty: {container_path}"
        
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        return True, data, ""
    except Exception as e:
        logger.error(f"Error copying and parsing JSON: {e}")
        return False, {}, str(e)
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)


def setup_vscode_verification(copy_from_env_fn: Callable, 
                              container_paths: List[str]) -> Tuple[bool, Dict[str, str], str]:
    """
    Set up verification environment by copying files from container
    
    Args:
        copy_from_env_fn: Function to copy files from container
        container_paths: List of file paths to copy from container
        
    Returns:
        Tuple of (success, file_paths_dict, error_message)
    """
    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_')
    file_paths = {}
    
    try:
        for container_path in container_paths:
            filename = os.path.basename(container_path)
            host_path = os.path.join(temp_dir, filename)
            
            try:
                copy_from_env_fn(container_path, host_path)
                if os.path.exists(host_path) and os.path.getsize(host_path) > 0:
                    file_paths[filename] = host_path
                else:
                    logger.warning(f"File not found or empty: {container_path}")
            except Exception as e:
                logger.warning(f"Failed to copy {container_path}: {e}")
        
        if not file_paths:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return False, {}, "No files were successfully copied"
        
        file_paths['temp_dir'] = temp_dir
        return True, file_paths, ""
    except Exception as e:
        shutil.rmtree(temp_dir, ignore_errors=True)
        return False, {}, str(e)


def cleanup_verification_temp(temp_dir: Optional[str] = None):
    """
    Clean up temporary verification files
    
    Args:
        temp_dir: Path to temp directory to clean up
    """
    if temp_dir and os.path.exists(temp_dir):
        try:
            shutil.rmtree(temp_dir)
            logger.debug(f"Cleaned up temp directory: {temp_dir}")
        except Exception as e:
            logger.warning(f"Failed to cleanup temp directory {temp_dir}: {e}")


def verify_git_commit_exists(repo_path: str, commit_message_pattern: str) -> bool:
    """
    Verify that a commit with matching message exists
    
    Args:
        repo_path: Path to Git repository
        commit_message_pattern: Pattern to match in commit message
        
    Returns:
        True if matching commit exists, False otherwise
    """
    commits = get_git_commits(repo_path, max_count=20)
    for commit in commits:
        if commit_message_pattern.lower() in commit['message'].lower():
            return True
    return False


def verify_file_contains(filepath: str, pattern: str, case_sensitive: bool = False) -> bool:
    """
    Verify that file contains a specific pattern
    
    Args:
        filepath: Path to file
        pattern: Pattern to search for
        case_sensitive: Whether search should be case-sensitive
        
    Returns:
        True if pattern found, False otherwise
    """
    content = read_file_content(filepath)
    if not content:
        return False
    
    if case_sensitive:
        return pattern in content
    else:
        return pattern.lower() in content.lower()


def verify_extension_installed(extensions_dir: str, extension_id: str) -> bool:
    """
    Verify that an extension is installed
    
    Args:
        extensions_dir: Path to extensions directory
        extension_id: Extension ID to check
        
    Returns:
        True if extension is installed, False otherwise
    """
    extensions = get_installed_extensions(extensions_dir)
    return check_extension_installed(extensions, extension_id)
