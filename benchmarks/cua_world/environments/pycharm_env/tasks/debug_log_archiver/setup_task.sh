#!/bin/bash
set -e
echo "=== Setting up debug_log_archiver task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="debug_log_archiver"
PROJECT_DIR="/home/ga/PycharmProjects/log_archiver"

# Clean up previous runs
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_result.json /tmp/${TASK_NAME}_start_ts 2>/dev/null || true

# Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/archiver $PROJECT_DIR/tests"

# --- requirements.txt ---
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
EOF

# --- archiver/__init__.py ---
touch "$PROJECT_DIR/archiver/__init__.py"

# --- archiver/validators.py (Contains Bug 3: NotImplemented stub) ---
cat > "$PROJECT_DIR/archiver/validators.py" << 'EOF'
"""Validation utilities for the archiver."""
import os
import shutil

class InsufficientSpaceError(Exception):
    pass

def check_disk_space(target_dir: str, required_bytes: int) -> bool:
    """
    Verify that target_dir has at least required_bytes available.
    
    Args:
        target_dir: Directory where archive will be stored.
        required_bytes: Number of bytes needed.
        
    Raises:
        InsufficientSpaceError: If free space is less than required.
    
    Returns:
        True if space is sufficient.
    """
    # BUG 3: Safety check is missing/stubbed
    # TODO: Implement disk space check using shutil.disk_usage
    # We need to check if free space > required_bytes
    raise NotImplementedError("Disk space check not implemented yet")
EOF

# --- archiver/core.py (Contains Bug 1: Unsafe delete, Bug 2: Strict Regex) ---
cat > "$PROJECT_DIR/archiver/core.py" << 'EOF'
"""Core archiving logic."""
import os
import shutil
import glob
import re
import logging
from typing import List
from .validators import check_disk_space, InsufficientSpaceError

logger = logging.getLogger(__name__)

def discover_log_files(log_dir: str) -> List[str]:
    """
    Find log files that need archiving.
    Expected format: app.log.YYYYMMDD or app.log.YYYY-MM-DD
    """
    files = glob.glob(os.path.join(log_dir, "*.log.*"))
    valid_files = []
    
    # BUG 2: Regex is too strict. It enforces \d{8} (YYYYMMDD) only.
    # It rejects ISO-8601 dates like 2023-10-25 used by the new logger.
    pattern = re.compile(r".*\.\d{8}$")
    
    for f in files:
        if pattern.match(f):
            valid_files.append(f)
            
    return sorted(valid_files)

def archive_file(source_path: str, dest_dir: str) -> str:
    """
    Compress a single log file and remove the original.
    
    Args:
        source_path: Full path to source log file.
        dest_dir: Directory to save .zip file.
        
    Returns:
        Path to created archive.
    """
    if not os.path.exists(source_path):
        raise FileNotFoundError(f"Source {source_path} not found")

    file_size = os.path.getsize(source_path)
    # Require 10% buffer overhead for safety
    required_space = int(file_size * 1.1)
    
    # Validate space (will fail until validators.py is fixed)
    check_disk_space(dest_dir, required_space)

    base_name = os.path.basename(source_path)
    archive_name = os.path.join(dest_dir, base_name)
    
    logger.info(f"Archiving {source_path} to {archive_name}.zip")
    
    try:
        # Create the zip archive
        # format="zip" adds .zip extension automatically
        shutil.make_archive(archive_name, 'zip', os.path.dirname(source_path), base_name)
        
    except Exception as e:
        logger.error(f"Failed to archive {source_path}: {e}")
        raise e
        
    finally:
        # BUG 1: CRITICAL DATA LOSS BUG
        # The finally block runs even if make_archive fails (e.g. disk full, permission denied).
        # We delete the source file before confirming the archive exists/is valid.
        if os.path.exists(source_path):
            logger.warning(f"Removing source file {source_path}")
            os.remove(source_path)
            
    return f"{archive_name}.zip"
EOF

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
import os
import tempfile
import shutil

@pytest.fixture
def temp_workspace():
    """Create a temporary workspace with source and dest directories."""
    tmp_dir = tempfile.mkdtemp()
    src_dir = os.path.join(tmp_dir, "logs")
    dest_dir = os.path.join(tmp_dir, "archive")
    os.makedirs(src_dir)
    os.makedirs(dest_dir)
    yield src_dir, dest_dir
    shutil.rmtree(tmp_dir)
EOF

# --- tests/test_validators.py ---
cat > "$PROJECT_DIR/tests/test_validators.py" << 'EOF'
import pytest
import shutil
from unittest.mock import patch
from archiver.validators import check_disk_space, InsufficientSpaceError

def test_check_disk_space_sufficient():
    """Test that check passes when ample space exists."""
    # Mock disk_usage to return 100GB free
    with patch('shutil.disk_usage') as mock_du:
        # total, used, free
        mock_du.return_value = (1000, 500, 100000)
        assert check_disk_space("/tmp", 500) is True

def test_check_disk_space_insufficient():
    """Test that check raises error when space is low."""
    # Mock disk_usage to return 100 bytes free
    with patch('shutil.disk_usage') as mock_du:
        mock_du.return_value = (1000, 900, 100)
        with pytest.raises(InsufficientSpaceError):
            check_disk_space("/tmp", 500)
EOF

# --- tests/test_core.py ---
cat > "$PROJECT_DIR/tests/test_core.py" << 'EOF'
import os
import pytest
import shutil
from unittest.mock import patch, MagicMock
from archiver.core import discover_log_files, archive_file
from archiver.validators import InsufficientSpaceError

# --- Discovery Tests ---

def test_discover_standard_dates(temp_workspace):
    src, _ = temp_workspace
    # Create standard format files
    open(os.path.join(src, "app.log.20230101"), "w").close()
    open(os.path.join(src, "db.log.20230520"), "w").close()
    
    files = discover_log_files(src)
    assert len(files) == 2

def test_discover_iso_dates(temp_workspace):
    """Bug 2: This test fails if regex doesn't support dashes."""
    src, _ = temp_workspace
    # Create ISO format files
    open(os.path.join(src, "app.log.2023-01-01"), "w").close()
    
    files = discover_log_files(src)
    assert len(files) == 1, "Should find files with ISO-8601 dates"
    assert "2023-01-01" in files[0]

# --- Archiving Safety Tests ---

def test_archive_success_removes_source(temp_workspace):
    src_dir, dest_dir = temp_workspace
    source_file = os.path.join(src_dir, "test.log")
    with open(source_file, "w") as f:
        f.write("content")
        
    # Mock validators to pass
    with patch('archiver.core.check_disk_space') as mock_check:
        mock_check.return_value = True
        archive_file(source_file, dest_dir)
        
    # Happy path: Source gone, Archive exists
    assert not os.path.exists(source_file), "Source should be removed on success"
    assert len(os.listdir(dest_dir)) == 1, "Archive should exist"

def test_archive_failure_preserves_source(temp_workspace):
    """Bug 1: This test fails if os.remove is in finally block."""
    src_dir, dest_dir = temp_workspace
    source_file = os.path.join(src_dir, "important.log")
    with open(source_file, "w") as f:
        f.write("DO NOT DELETE ME")
        
    # Mock make_archive to fail (simulate disk full or permission error)
    with patch('shutil.make_archive', side_effect=OSError("Disk full")):
        with patch('archiver.core.check_disk_space', return_value=True):
            with pytest.raises(OSError):
                archive_file(source_file, dest_dir)
    
    # Critical assertion: Source file must still exist!
    assert os.path.exists(source_file), "CRITICAL: Source file was deleted after archive failure!"

def test_archive_checks_disk_space(temp_workspace):
    src_dir, dest_dir = temp_workspace
    source_file = os.path.join(src_dir, "big.log")
    with open(source_file, "w") as f:
        f.write("x" * 1000)
        
    # Ensure check_disk_space is actually called
    with patch('archiver.core.check_disk_space', side_effect=InsufficientSpaceError):
        with pytest.raises(InsufficientSpaceError):
            archive_file(source_file, dest_dir)
            
    # File should still exist
    assert os.path.exists(source_file)
EOF

# Set proper ownership
chown -R ga:ga "$PROJECT_DIR"

# Launch PyCharm
echo "Launching PyCharm..."
setup_pycharm_project "$PROJECT_DIR" "log_archiver"

# Wait for indexing
sleep 10

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="