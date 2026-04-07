#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Repair In-Memory Cache Task ==="

WORKSPACE_DIR="/home/ga/workspace/pycache"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Record task start time
date +%s > /tmp/task_start_time.txt

# ─── src/lru.py ────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/lru.py" << 'EOF'
class Node:
    def __init__(self, key, value):
        self.key = key
        self.value = value
        self.prev = None
        self.next = None

class LRUCache:
    def __init__(self, capacity: int):
        self.capacity = capacity
        self.cache = {}
        self.head = Node(None, None)
        self.tail = Node(None, None)
        self.head.next = self.tail
        self.tail.prev = self.head

    def put(self, key, value):
        if key in self.cache:
            node = self.cache[key]
            node.value = value
            self._move_to_front(node)
        else:
            if len(self.cache) >= self.capacity:
                lru = self.tail.prev
                self._remove(lru)
                del self.cache[lru.key]
            new_node = Node(key, value)
            self.cache[key] = new_node
            self._insert_front(new_node)

    def get(self, key):
        if key in self.cache:
            node = self.cache[key]
            self._move_to_front(node)
            return node.value
        return -1

    def _remove(self, node):
        node.prev.next = node.next
        # BUG: Forgot to update node.next.prev!

    def _insert_front(self, node):
        node.next = self.head.next
        node.prev = self.head
        self.head.next.prev = node
        self.head.next = node

    def _move_to_front(self, node):
        self._remove(node)
        self._insert_front(node)
EOF

# ─── src/ttl.py ────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/ttl.py" << 'EOF'
import time

class TTLCache:
    def __init__(self):
        self.store = {}
        self.expires = {}

    def sweep(self):
        """Called periodically by a background thread to clear expired keys."""
        now = time.time()
        # BUG: RuntimeError: dictionary changed size during iteration
        for k, expire_at in self.expires.items():
            if now > expire_at:
                del self.store[k]
                del self.expires[k]
EOF

# ─── src/wal.py ────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/wal.py" << 'EOF'
import time

class WriteAheadLog:
    def __init__(self, path):
        self.path = path

    def log_expire(self, key, ttl_seconds):
        """Logs an expiration event."""
        # BUG: Logs relative TTL instead of absolute timestamp.
        # Upon crash recovery, keys get resurrected with a fresh TTL.
        with open(self.path, "a") as f:
            f.write(f"EXPIRE {key} {ttl_seconds}\n")
EOF

# ─── src/sharding.py ───────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/sharding.py" << 'EOF'
def get_hash_tag(key: str) -> str:
    """
    Extracts the hash tag from a key for cluster sharding.
    If the key contains '{}', the substring between the first '{' and the first '}' is the tag.
    """
    start = key.find('{')
    if start == -1:
        return key
    # BUG: uses rfind instead of find, taking the widest match
    end = key.rfind('}')
    
    if end != -1 and end > start:
        return key[start+1:end]
    return key
EOF

# ─── src/sorted_set.py ─────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/sorted_set.py" << 'EOF'
class SortedSet:
    def __init__(self):
        self.data = []

    def add(self, member, score):
        """Adds a member with a score, maintaining sorted order."""
        # Remove if already exists
        self.data = [x for x in self.data if x[1] != member]
        # Append new
        self.data.append((score, member))
        
        # BUG: lambda x: x[0] ignores member for tie-breaking
        self.data.sort(key=lambda x: x[0])
EOF

# ─── tests/test_all.py ─────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_all.py" << 'EOF'
import time
import os
import pytest
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.lru import LRUCache
from src.ttl import TTLCache
from src.wal import WriteAheadLog
from src.sharding import get_hash_tag
from src.sorted_set import SortedSet

def test_lru_eviction():
    cache = LRUCache(2)
    cache.put("a", 1)
    cache.put("b", 2)
    cache.get("a")
    cache.put("c", 3)
    
    curr = cache.tail.prev
    backward_keys = []
    while curr != cache.head:
        backward_keys.append(curr.key)
        curr = curr.prev
    assert backward_keys == ["c", "a"], "Backward pointers broken in LRU _remove"

def test_ttl_sweep():
    cache = TTLCache()
    cache.store["k1"] = "v1"
    cache.expires["k1"] = time.time() - 10
    cache.store["k2"] = "v2"
    cache.expires["k2"] = time.time() + 10
    
    cache.sweep()  # Should not raise RuntimeError
    assert "k1" not in cache.store
    assert "k2" in cache.store

def test_wal_absolute_time():
    wal_file = "test.wal"
    if os.path.exists(wal_file): os.remove(wal_file)
    wal = WriteAheadLog(wal_file)
    
    wal.log_expire("key1", 60)
    
    with open(wal_file) as f:
        content = f.read()
    
    assert any(str(int(time.time()))[:5] in token for token in content.split()), \
        "WAL must log an absolute timestamp (e.g., time.time() + ttl_seconds)"

def test_sharding_tags():
    assert get_hash_tag("user:{123}") == "123"
    assert get_hash_tag("user:{123}:session:{abc}") == "123", "Should take the first enclosed {}"

def test_sorted_set_tie():
    s = SortedSet()
    s.add("b", 10)
    s.add("a", 10)
    s.add("c", 5)
    
    assert [x[1] for x in s.data] == ["c", "a", "b"], "Scores are tied; should sort lexicographically by member"
EOF

chown -R ga:ga "$WORKSPACE_DIR"

# Launch VS Code
echo "Launching VS Code..."
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR" &
sleep 5

# Focus and maximize
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="