#!/bin/bash
echo "=== Setting up fix_deduplication_utility task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/smart_dedup"

# Clean previous state
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/dedup_result.json /tmp/dedup_start_ts 2>/dev/null || true

# Record start time
date +%s > /tmp/dedup_start_ts

# Create directories
su - ga -c "mkdir -p $PROJECT_DIR/tests $PROJECT_DIR/data"

# --- Create smart_dedup.py (The buggy implementation) ---
cat > "$PROJECT_DIR/smart_dedup.py" << 'PYEOF'
"""
Smart Deduplication Utility
Scans a directory and replaces duplicate files with hardlinks.
"""
import hashlib
import os
import sys
from pathlib import Path


def get_file_hash(filepath: Path) -> str:
    """
    Calculate hash of a file to identify duplicates.
    Optimization: Only read the beginning of the file for speed.
    """
    h = hashlib.md5()
    try:
        with open(filepath, 'rb') as f:
            # BUG 1: Partial hashing. Only reads first 2KB.
            # Files identical in header but different in tail will collide.
            chunk = f.read(2048)
            if chunk:
                h.update(chunk)
    except IOError:
        return ""
    return h.hexdigest()


def find_duplicates(directory: Path):
    """
    Scan directory and group files by hash.
    Returns dict: {hash: [list of files]}
    """
    hashes = {}
    for root, _, files in os.walk(directory):
        for filename in files:
            filepath = Path(root) / filename
            
            # Skip symlinks
            if filepath.is_symlink():
                continue
                
            try:
                stat = filepath.stat()
                size = stat.st_size
                
                # BUG 3: Arbitrary size filter.
                # Ignores files smaller than 1KB, missing config files/scripts.
                if size < 1024:
                    continue
                    
                file_hash = get_file_hash(filepath)
                
                if file_hash:
                    if file_hash not in hashes:
                        hashes[file_hash] = []
                    hashes[file_hash].append(filepath)
            except IOError:
                continue
    
    # Filter for only actual duplicates (more than 1 file)
    return {k: v for k, v in hashes.items() if len(v) > 1}


def deduplicate_files(duplicates: dict):
    """
    Replace duplicates with hardlinks.
    """
    count = 0
    saved_bytes = 0
    
    for file_hash, file_list in duplicates.items():
        # Keep the first one as the source
        source = file_list[0]
        targets = file_list[1:]
        
        for target in targets:
            try:
                print(f"Linking {target} -> {source}")
                # BUG 2: os.link raises FileExistsError if target exists.
                # Must remove target before linking.
                os.link(source, target)
                
                count += 1
                saved_bytes += source.stat().st_size
            except OSError as e:
                print(f"Error processing {target}: {e}")
                
    return count, saved_bytes


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python smart_dedup.py <directory>")
        sys.exit(1)
        
    target_dir = Path(sys.argv[1])
    if not target_dir.exists():
        print(f"Directory not found: {target_dir}")
        sys.exit(1)
        
    print(f"Scanning {target_dir}...")
    dupes = find_duplicates(target_dir)
    print(f"Found {len(dupes)} groups of duplicates.")
    
    c, b = deduplicate_files(dupes)
    print(f"Deduplication complete. Linked {c} files, saved {b} bytes.")
PYEOF

# --- Create tests/test_dedup.py ---
cat > "$PROJECT_DIR/tests/test_dedup.py" << 'PYEOF'
import os
import pytest
from pathlib import Path
import smart_dedup
import time

@pytest.fixture
def test_dir(tmp_path):
    """Create a temporary directory with test data."""
    d = tmp_path / "data"
    d.mkdir()
    return d

def test_partial_hash_collision(test_dir):
    """
    Regression Test for Bug 1: Partial Hashing.
    Creates two files that are identical in the first 2KB but different after.
    They must NOT be treated as duplicates.
    """
    # Create common header > 2KB
    header = b"A" * 2048
    
    file1 = test_dir / "file1.bin"
    file1.write_bytes(header + b"DATA_ONE")
    
    file2 = test_dir / "file2.bin"
    file2.write_bytes(header + b"DATA_TWO")
    
    # Run duplicate detection
    dupes = smart_dedup.find_duplicates(test_dir)
    
    # If hashing is partial, these will be grouped together (incorrectly)
    # If hashing is full, they will be distinct (hashes won't match, so no dupes returned)
    assert len(dupes) == 0, "Data integrity failure: Distinct files treated as duplicates due to partial hashing!"

def test_exact_duplicate_detection(test_dir):
    """Verify that actual duplicates are found."""
    content = b"X" * 3000
    (test_dir / "dup1.bin").write_bytes(content)
    (test_dir / "dup2.bin").write_bytes(content)
    
    dupes = smart_dedup.find_duplicates(test_dir)
    assert len(dupes) == 1
    assert len(list(dupes.values())[0]) == 2

def test_small_files_ignored(test_dir):
    """
    Regression Test for Bug 3: Size Filter.
    Small files (<1KB) should also be deduplicated.
    """
    content = b"Small configuration file content"
    (test_dir / "small1.conf").write_bytes(content)
    (test_dir / "small2.conf").write_bytes(content)
    
    dupes = smart_dedup.find_duplicates(test_dir)
    assert len(dupes) > 0, "Small files were ignored by scanner!"

def test_hardlink_crash(test_dir):
    """
    Regression Test for Bug 2: FileExistsError.
    Deduplication should replace the file, not crash.
    """
    content = b"Z" * 4000
    f1 = test_dir / "source.bin"
    f2 = test_dir / "target.bin"
    f1.write_bytes(content)
    f2.write_bytes(content)
    
    # Manually construct duplicate dict to test deduplicate_files function isolation
    # Hash doesn't matter for this test, just the linking logic
    dupes = {"dummy_hash": [f1, f2]}
    
    try:
        count, _ = smart_dedup.deduplicate_files(dupes)
    except FileExistsError:
        pytest.fail("Crashed with FileExistsError! Target must be removed before linking.")
        
    assert count == 1
    # Verify they are now hardlinked (same inode)
    assert f1.stat().st_ino == f2.stat().st_ino

PYEOF

# --- Setup PyCharm Project ---
# We use the setup_pycharm_project utility from task_utils.sh
setup_pycharm_project "$PROJECT_DIR" "smart_dedup"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="