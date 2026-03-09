"""
VSCode verification utilities for gym-anything tasks
"""

from .vscode_verification_utils import (
    parse_vscode_settings,
    parse_launch_json,
    get_installed_extensions,
    check_extension_installed,
    get_git_commits,
    get_git_status,
    read_file_content,
    check_file_exists,
    setup_vscode_verification,
    cleanup_verification_temp,
    copy_and_parse_json,
    verify_git_commit_exists,
    verify_file_contains,
    verify_extension_installed
)

__all__ = [
    'parse_vscode_settings',
    'parse_launch_json',
    'get_installed_extensions',
    'check_extension_installed',
    'get_git_commits',
    'get_git_status',
    'read_file_content',
    'check_file_exists',
    'setup_vscode_verification',
    'cleanup_verification_temp',
    'copy_and_parse_json',
    'verify_git_commit_exists',
    'verify_file_contains',
    'verify_extension_installed'
]
