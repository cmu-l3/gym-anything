#!/bin/bash
set -e

echo "=== Setting up fix_key_value_store task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_key_value_store"
PROJECT_DIR="/home/ga/PycharmProjects/pylsm_engine"

# Cleanup previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_* 2>/dev/null || true

# Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# Create directories
mkdir -p "$PROJECT_DIR/pylsm"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/data"

# Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
EOF

# ==============================================================================
# 1. Generate Real-World Data (Webster's Dictionary Subset)
# ==============================================================================
echo "Generating dataset..."
cat > "$PROJECT_DIR/data/generate_data.py" << 'PYEOF'
import json
import random

# Real dictionary words to ensure realistic key distribution (prefixes, lengths)
# Source: Public domain word lists
seeds = [
    "apple", "application", "apply", "apricot", "april", "aptitude",
    "binary", "bind", "bingo", "biology", "biotope", "biscuit",
    "cache", "cackle", "cactus", "cadet", "cafe", "cage",
    "data", "database", "date", "datum", "daunt", "dawn",
    "zebra", "zenith", "zephyr", "zero", "zest", "zigzag"
]

data = {}
# Generate 1000 entries
for i in range(1000):
    seed = seeds[i % len(seeds)]
    key = f"{seed}_{i}"
    # Value mimics a JSON definitions blob
    value = json.dumps({
        "id": i,
        "word": key,
        "definition": f"A generated definition for {key} used in testing.",
        "usage": f"Example usage of {key} in a sentence."
    })
    data[key] = value

with open("webster_sample.json", "w") as f:
    json.dump(data, f, indent=2)
PYEOF

cd "$PROJECT_DIR/data" && python3 generate_data.py && rm generate_data.py

# ==============================================================================
# 2. Create Source Code (With Bugs)
# ==============================================================================

# --- pylsm/__init__.py ---
touch "$PROJECT_DIR/pylsm/__init__.py"

# --- pylsm/memtable.py (No bugs) ---
cat > "$PROJECT_DIR/pylsm/memtable.py" << 'PYEOF'
"""In-memory storage component (MemTable)."""
class MemTable:
    def __init__(self):
        self._data = {}
        self._size_bytes = 0

    def put(self, key, value):
        self._data[key] = value
        self._size_bytes += len(key) + len(value)

    def get(self, key):
        return self._data.get(key)

    def delete(self, key):
        # Tombstone marker
        self._data[key] = b'\x00DELETED'
        self._size_bytes += len(key) + 8

    def __iter__(self):
        for k in sorted(self._data.keys()):
            yield k, self._data[k]

    def clear(self):
        self._data.clear()
        self._size_bytes = 0

    @property
    def size(self):
        return self._size_bytes
PYEOF

# --- pylsm/sstable.py (BUG 1: Binary Search) ---
cat > "$PROJECT_DIR/pylsm/sstable.py" << 'PYEOF'
"""SSTable implementation (Sorted String Table on disk)."""
import os
import json
import struct

class SSTable:
    def __init__(self, filepath):
        self.filepath = filepath
        self.index = []  # List of (key, offset) tuples
        self._load_index()

    def _load_index(self):
        """Load the sparse index from the file footer."""
        if not os.path.exists(self.filepath):
            return
        
        with open(self.filepath, 'rb') as f:
            f.seek(0, 2)
            file_size = f.tell()
            if file_size < 8:
                return
            
            # Read index offset
            f.seek(-8, 2)
            index_offset = struct.unpack('<Q', f.read(8))[0]
            
            # Read index
            f.seek(index_offset)
            index_data = f.read(file_size - index_offset - 8)
            try:
                self.index = json.loads(index_data.decode('utf-8'))
            except:
                self.index = []

    def get(self, key):
        """Retrieve value for key from disk."""
        if not self.index:
            return None
            
        block_offset = self._find_block(key)
        if block_offset is None:
            return None
            
        return self._scan_block(block_offset, key)

    def _find_block(self, key):
        """Binary search the sparse index to find the starting block."""
        low = 0
        high = len(self.index) - 1
        
        # BUG 1: Binary search off-by-one/boundary error.
        # This implementation fails to find keys in the last block correctly
        # or handles the upper bound incorrectly.
        best_offset = None
        
        while low <= high:
            mid = (low + high) // 2
            mid_key = self.index[mid][0]
            
            if mid_key <= key:
                best_offset = self.index[mid][1]
                low = mid + 1
            else:
                # BUG: Should be 'mid - 1', logic here causes issues finding exact bounds
                high = mid 
                if low == high: # Prevention of infinite loop but wrong logic
                    break

        return best_offset

    def _scan_block(self, offset, key):
        """Linear scan within a block."""
        with open(self.filepath, 'rb') as f:
            f.seek(offset)
            # Simple format: length-prefixed blocks (simplified for task)
            # Read until we find key or hit next block/EOF
            # In a real system, we'd read chunks. Here we read 4KB.
            chunk = f.read(4096) 
            data_str = chunk.decode('utf-8', errors='ignore')
            
            # Simplified parsing: "key:value\n"
            lines = data_str.split('\n')
            for line in lines:
                if ':' not in line: continue
                k, v = line.split(':', 1)
                if k == key:
                    return v
        return None

    @classmethod
    def create(cls, filepath, iterator):
        """Create a new SSTable from an iterator of (key, value)."""
        index = []
        with open(filepath, 'wb') as f:
            current_offset = 0
            count = 0
            for k, v in iterator:
                # Write entry
                entry = f"{k}:{v}\n".encode('utf-8')
                f.write(entry)
                
                # Add to index every 10 items (sparse index)
                if count % 10 == 0:
                    index.append((k, current_offset))
                
                current_offset += len(entry)
                count += 1
            
            # Write index at end
            index_data = json.dumps(index).encode('utf-8')
            index_offset = f.tell()
            f.write(index_data)
            f.write(struct.pack('<Q', index_offset))
            
        return cls(filepath)
PYEOF

# --- pylsm/compaction.py (BUG 2: Merge Priority) ---
cat > "$PROJECT_DIR/pylsm/compaction.py" << 'PYEOF'
"""Compaction logic for merging SSTables."""

def merge_iterators(iter1, iter2):
    """
    Merge two sorted iterators.
    iter1: Newer data (e.g., MemTable)
    iter2: Older data (e.g., SSTable on disk)
    
    Should yield unique keys, preferring iter1 when keys match.
    """
    try:
        k1, v1 = next(iter1)
    except StopIteration:
        yield from iter2
        return

    try:
        k2, v2 = next(iter2)
    except StopIteration:
        yield (k1, v1)
        yield from iter1
        return

    while True:
        if k1 < k2:
            yield (k1, v1)
            try:
                k1, v1 = next(iter1)
            except StopIteration:
                yield (k2, v2)
                yield from iter2
                return
        elif k2 < k1:
            yield (k2, v2)
            try:
                k2, v2 = next(iter2)
            except StopIteration:
                yield (k1, v1)
                yield from iter1
                return
        else:
            # Keys are equal.
            # BUG 2: Priority Inversion.
            # We are yielding (k2, v2) which is from iter2 (OLDER data).
            # We SHOULD yield (k1, v1) which is NEWER.
            yield (k2, v2)
            
            try:
                k1, v1 = next(iter1)
                k2, v2 = next(iter2)
            except StopIteration:
                # Logic to drain remaining is omitted for brevity in bug demo
                return
PYEOF

# --- pylsm/lsm.py (BUG 3: Tombstone) ---
cat > "$PROJECT_DIR/pylsm/lsm.py" << 'PYEOF'
"""Main LSM Tree engine."""
import os
import shutil
from .memtable import MemTable
from .sstable import SSTable
from .compaction import merge_iterators

TOMBSTONE = 'DELETED'

class LSMTree:
    def __init__(self, data_dir):
        self.data_dir = data_dir
        os.makedirs(data_dir, exist_ok=True)
        self.memtable = MemTable()
        self.sstables = [] # List of SSTable objects, [0] is newest
        self._load_manifest()

    def _load_manifest(self):
        # Simplified: just look for sstable_*.db files
        files = sorted([f for f in os.listdir(self.data_dir) if f.startswith('sst_')])
        for f in reversed(files): # Newest first
            self.sstables.append(SSTable(os.path.join(self.data_dir, f)))

    def put(self, key, value):
        self.memtable.put(key, value)
        if self.memtable.size > 1024 * 10: # 10KB flush threshold
            self.flush()

    def get(self, key):
        # 1. Check Memtable
        val = self.memtable.get(key)
        if val is not None:
            if val == b'\x00DELETED':
                return None
            return val

        # 2. Check SSTables (Newest to Oldest)
        for sst in self.sstables:
            val = sst.get(key)
            if val is not None:
                # BUG 3: Tombstone Fallthrough
                # If we find a tombstone in a newer SSTable, we should stop and return None.
                # Instead, this code ignores it and keeps looking in older SSTables,
                # potentially resurrecting a deleted value.
                if val == TOMBSTONE:
                    pass # Continues to next SSTable...
                else:
                    return val
        
        return None

    def delete(self, key):
        self.memtable.put(key, TOMBSTONE)

    def flush(self):
        filename = f"sst_{len(self.sstables):05d}.db"
        filepath = os.path.join(self.data_dir, filename)
        
        # Write memtable to disk
        new_sst = SSTable.create(filepath, self.memtable)
        self.sstables.insert(0, new_sst)
        self.memtable.clear()

    def compact(self):
        """Simplified compaction: merge all SSTables into one."""
        if not self.sstables:
            return

        # Create iterator for current state
        # In real LSM, we'd cascade. Here we just merge newest with next newest...
        # For simplicity of the task, let's just say we aren't implementing full compaction
        # in the test harness, but the merge logic is used elsewhere.
        pass
PYEOF

# ==============================================================================
# 3. Create Tests
# ==============================================================================

cat > "$PROJECT_DIR/tests/test_pylsm.py" << 'PYEOF'
import pytest
import os
import shutil
import json
from pylsm.lsm import LSMTree
from pylsm.compaction import merge_iterators

DATA_DIR = "/tmp/pylsm_test_data"

@pytest.fixture
def db():
    if os.path.exists(DATA_DIR):
        shutil.rmtree(DATA_DIR)
    return LSMTree(DATA_DIR)

def test_basic_put_get(db):
    db.put("key1", "value1")
    assert db.get("key1") == "value1"

def test_overwrite(db):
    db.put("key1", "value1")
    db.put("key1", "value2")
    assert db.get("key1") == "value2"

def test_delete(db):
    db.put("key1", "value1")
    db.delete("key1")
    assert db.get("key1") is None

def test_flush_and_persistence(db):
    # Write enough to force flush (threshold is 10KB)
    large_val = "x" * 1000
    for i in range(15):
        db.put(f"key{i}", large_val)
    
    # Should have flushed to SSTable
    assert len(db.sstables) > 0
    
    # Check data retrieval from disk
    assert db.get("key0") == large_val
    assert db.get("key14") == large_val

def test_binary_search_boundary(db):
    # This tests BUG 1 (SSTable binary search)
    # We construct a scenario where keys land at block boundaries
    
    # Create manual SSTable
    data = [(f"k{i:03d}", f"v{i}") for i in range(100)]
    # k000, k001, ..., k099
    
    # Force flush
    for k, v in data:
        db.put(k, v)
    db.flush()
    
    # Try to get the very last key (often fails with off-by-one high bound)
    assert db.get("k099") == "v99"
    # Try to get a key that doesn't exist but is greater than all
    assert db.get("k100") is None

def test_merge_priority(db):
    # Tests BUG 2 (Merge Priority Inversion)
    # Simulate a merge:
    # iter1 (Newer): [('a', 'new')]
    # iter2 (Older): [('a', 'old')]
    
    iter1 = iter([('a', 'new')])
    iter2 = iter([('a', 'old')])
    
    merged = list(merge_iterators(iter1, iter2))
    
    # Should be ('a', 'new')
    assert len(merged) == 1
    assert merged[0] == ('a', 'new'), "Compaction preserved older value!"

def test_tombstone_masking(db):
    # Tests BUG 3 (Tombstone handling)
    
    # 1. Write 'key1' -> 'val1' and flush to SSTable 1 (Old)
    db.put("key1", "val1")
    # Force flush
    db.memtable._size_bytes = 99999
    db.flush()
    
    # 2. Delete 'key1' and flush to SSTable 0 (New)
    db.delete("key1")
    db.memtable._size_bytes = 99999
    db.flush()
    
    # Now we have:
    # SSTable 0 (Newer): key1 -> DELETED
    # SSTable 1 (Older): key1 -> val1
    
    # db.get('key1') should see DELETED in SST0 and stop.
    # The bug causes it to fall through to SST1 and return 'val1'.
    
    val = db.get("key1")
    assert val is None, f"Zombie key resurrection! Expected None, got {val}"

def test_real_data_consistency(db):
    # Use the provided Webster sample
    with open("../data/webster_sample.json", "r") as f:
        data = json.load(f)
        
    keys = list(data.keys())
    
    # Write half
    for k in keys[:500]:
        db.put(k, data[k])
    
    db.flush()
    
    # Write second half
    for k in keys[500:]:
        db.put(k, data[k])
        
    # Verify random samples
    import random
    for _ in range(50):
        k = random.choice(keys)
        assert db.get(k) == data[k]

PYEOF

# Ensure ga user owns everything
chown -R ga:ga "$PROJECT_DIR"

# Wait for PyCharm
wait_for_pycharm 120

# Open project in PyCharm
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /dev/null 2>&1 &"
sleep 10
dismiss_dialogs 5
focus_pycharm_window
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="