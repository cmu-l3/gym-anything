#!/bin/bash
echo "=== Setting up debug_concurrent_cache task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="debug_concurrent_cache"
PROJECT_DIR="/home/ga/PycharmProjects/concurrent_cache"

# 1. Clean previous state
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f /tmp/tests_checksum.md5 2>/dev/null || true

# 2. Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/cache $PROJECT_DIR/tests"

# 3. Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
pytest-timeout>=2.1.0
EOF

# 4. Create Source Code (Buggy)

# --- cache/__init__.py ---
touch "$PROJECT_DIR/cache/__init__.py"

# --- cache/lru_cache.py ---
# Bug 1: _evict_oldest called outside lock
# Bug 3: Stats updated outside lock
cat > "$PROJECT_DIR/cache/lru_cache.py" << 'EOF'
import threading
from collections import OrderedDict

class ThreadSafeLRUCache:
    def __init__(self, capacity: int):
        self._capacity = capacity
        self._cache = OrderedDict()
        self._lock = threading.RLock()
        self._hits = 0
        self._misses = 0

    def get(self, key):
        with self._lock:
            if key in self._cache:
                self._cache.move_to_end(key)
                val = self._cache[key]
                found = True
            else:
                val = -1
                found = False
        
        # BUG 3: Stats update outside lock (race condition on non-atomic increment)
        if found:
            self._hits += 1
            return val
        else:
            self._misses += 1
            return -1

    def put(self, key, value):
        should_evict = False
        
        with self._lock:
            if key in self._cache:
                self._cache.move_to_end(key)
            self._cache[key] = value
            
            if len(self._cache) > self._capacity:
                should_evict = True

        # BUG 1: Eviction happens outside lock
        # Multiple threads can enter here simultaneously and try to evict
        if should_evict:
            self._evict_oldest()

    def _evict_oldest(self):
        # Helper that assumes it handles its own locking or is called safely
        # But in the buggy version, it's called without the lock held!
        if len(self._cache) > 0:
            try:
                self._cache.popitem(last=False)
            except KeyError:
                # Concurrent pop might cause this if guarded poorly
                pass

    def get_stats(self):
        with self._lock:
            return {"hits": self._hits, "misses": self._misses, "size": len(self._cache)}
EOF

# --- cache/ttl_cache.py ---
# Bug 2: Deadlock in resize vs put (Lock ordering inversion)
# Bug 4: TOCTOU in get (check time -> release lock -> delete)
cat > "$PROJECT_DIR/cache/ttl_cache.py" << 'EOF'
import time
import threading
from .lru_cache import ThreadSafeLRUCache

class ThreadSafeTTLCache(ThreadSafeLRUCache):
    def __init__(self, capacity: int, ttl_seconds: int):
        super().__init__(capacity)
        self._ttl = ttl_seconds
        self._timestamps = {}
        # Secondary lock for metadata/resizing operations
        self._meta_lock = threading.RLock()

    def put(self, key, value):
        # Acquire main lock first
        with self._lock:
            super().put(key, value)
            self._timestamps[key] = time.time()
            
            # Check for immediate resize trigger (simulated complex logic)
            self._check_resize_trigger()

    def get(self, key):
        # BUG 4: TOCTOU race on expiry check
        # Checks timestamp, releases lock (implicitly), then deletes if expired
        
        timestamp = 0
        with self._lock:
            if key not in self._timestamps:
                return -1
            timestamp = self._timestamps[key]
        
        # Check expiry outside main lock (or logic gap)
        if time.time() - timestamp > self._ttl:
            # Race: Another thread could have updated the key/timestamp right here!
            with self._lock:
                if key in self._cache:
                    del self._cache[key]
                if key in self._timestamps:
                    del self._timestamps[key]
            return -1
            
        return super().get(key)

    def _check_resize_trigger(self):
        # Internal method called while holding _lock
        # If we need to sync with meta operations, we might grab _meta_lock
        pass

    def resize(self, new_capacity):
        # BUG 2: Deadlock potential via Lock Ordering Inversion
        # resize: grabs _meta_lock -> then grabs _lock
        # put: grabs _lock -> calls _check_resize_trigger -> (if we add logic) grabs _meta_lock
        
        # To make the deadlock reproducible in tests, we explicitly conflict 
        # with a simulated heavy operation in put
        with self._meta_lock:
            # Simulate work
            time.sleep(0.01)
            with self._lock:
                self._capacity = new_capacity
                while len(self._cache) > self._capacity:
                    self._evict_oldest()

    # Overriding to introduce the deadlock dependency
    def _evict_oldest(self):
        # In TTL cache, eviction might want to update metadata stats
        with self._meta_lock:
             super()._evict_oldest()
EOF

# 5. Create Test Suite

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
import time
import threading
from cache.lru_cache import ThreadSafeLRUCache
from cache.ttl_cache import ThreadSafeTTLCache

@pytest.fixture
def lru_cache():
    return ThreadSafeLRUCache(capacity=50)

@pytest.fixture
def ttl_cache():
    return ThreadSafeTTLCache(capacity=50, ttl_seconds=1)
EOF

# --- tests/test_lru_basic.py (Single threaded - PASSING) ---
cat > "$PROJECT_DIR/tests/test_lru_basic.py" << 'EOF'
def test_put_get(lru_cache):
    lru_cache.put("a", 1)
    assert lru_cache.get("a") == 1

def test_miss(lru_cache):
    assert lru_cache.get("missing") == -1

def test_eviction(lru_cache):
    # capacity is 50
    for i in range(60):
        lru_cache.put(f"key{i}", i)
    
    assert lru_cache.get_stats()["size"] == 50
    # 0-9 should be evicted
    assert lru_cache.get("key0") == -1
    assert lru_cache.get("key59") == 59
EOF

# --- tests/test_lru_concurrent.py (Multi threaded - FAILING) ---
cat > "$PROJECT_DIR/tests/test_lru_concurrent.py" << 'EOF'
import threading
import pytest
import time
from cache.lru_cache import ThreadSafeLRUCache

def test_concurrent_stats_accuracy():
    # Bug 3: Stats race
    cache = ThreadSafeLRUCache(capacity=1000)
    threads = []
    
    def worker():
        for i in range(100):
            cache.put(f"k{i}", i)
            cache.get(f"k{i}") # Hit
            cache.get("missing") # Miss

    for _ in range(10):
        t = threading.Thread(target=worker)
        threads.append(t)
        t.start()
        
    for t in threads:
        t.join()
        
    stats = cache.get_stats()
    # 10 threads * 100 iters = 1000 hits, 1000 misses
    # With race condition, these numbers will be lower
    assert stats["hits"] == 1000, f"Expected 1000 hits, got {stats['hits']}"
    assert stats["misses"] == 1000, f"Expected 1000 misses, got {stats['misses']}"

def test_concurrent_eviction_integrity():
    # Bug 1: Eviction race
    # Small capacity, many threads inserting unique keys
    cache = ThreadSafeLRUCache(capacity=10)
    stop = False
    errors = []
    
    def writer():
        i = 0
        while not stop:
            try:
                cache.put(f"key{i}", i)
                i += 1
            except Exception as e:
                errors.append(e)
                break

    threads = [threading.Thread(target=writer) for _ in range(5)]
    for t in threads:
        t.start()
        
    time.sleep(2)
    stop = True
    for t in threads:
        t.join()
        
    # If _evict_oldest runs concurrently on OrderedDict without lock, 
    # it often raises KeyError or corrupts structure
    assert not errors, f"Errors occurred during concurrent eviction: {errors}"
    
    # Size check strictly
    stats = cache.get_stats()
    # It might be slightly > 10 momentarily if loose locking, but hard assertion helps finding bug
    # Actually, verify consistency: size should verify
    assert stats["size"] <= 10, f"Cache grew beyond capacity: {stats['size']}"
EOF

# --- tests/test_ttl_basic.py (PASSING) ---
cat > "$PROJECT_DIR/tests/test_ttl_basic.py" << 'EOF'
import time
import pytest

def test_ttl_expiry(ttl_cache):
    ttl_cache.put("a", 1)
    assert ttl_cache.get("a") == 1
    time.sleep(1.1)
    assert ttl_cache.get("a") == -1
EOF

# --- tests/test_ttl_concurrent.py (FAILING) ---
cat > "$PROJECT_DIR/tests/test_ttl_concurrent.py" << 'EOF'
import threading
import time
import pytest
from cache.ttl_cache import ThreadSafeTTLCache

@pytest.mark.timeout(5)
def test_deadlock_resize_put():
    # Bug 2: Deadlock
    cache = ThreadSafeTTLCache(capacity=1000, ttl_seconds=60)
    stop = False
    
    def resizing_worker():
        while not stop:
            cache.resize(500)
            time.sleep(0.01)
            cache.resize(1000)
            time.sleep(0.01)
            
    def put_worker():
        i = 0
        while not stop:
            # Fill to trigger internal checks
            cache.put(f"k{i}", i)
            i = (i + 1) % 2000
            
    t1 = threading.Thread(target=resizing_worker)
    t2 = threading.Thread(target=put_worker)
    
    t1.start()
    t2.start()
    
    time.sleep(3)
    stop = True
    
    t1.join()
    t2.join()
    # If deadlock occurs, join will hang (timeout fixture handles failure)

def test_ttl_update_race():
    # Bug 4: TOCTOU
    # Thread A: Reads key (expired) -> sleeps -> deletes
    # Thread B: Puts key (new)
    # Thread A: Deletes key (WRONG - deleted the NEW valid key)
    
    cache = ThreadSafeTTLCache(capacity=10, ttl_seconds=0.1)
    
    # 1. Insert key and let it expire
    cache.put("target", "old_value")
    time.sleep(0.2) 
    
    # 2. Race condition setup
    stop = False
    success = False
    
    def refresher():
        # Continually puts new value
        while not stop:
            cache.put("target", "new_value")
            time.sleep(0.001)
            
    def getter():
        # Continually gets (triggering expiry check)
        while not stop:
            cache.get("target")
            time.sleep(0.001)
            
    t1 = threading.Thread(target=refresher)
    t2 = threading.Thread(target=getter)
    t1.start()
    t2.start()
    
    time.sleep(1)
    stop = True
    t1.join()
    t2.join()
    
    # Finally, key should exist and be "new_value"
    # If the bug triggers, the getter deleted the "new_value" thinking it was the "old_value"
    val = cache.get("target")
    
    # Note: get() might return -1 if we hit exact expiry, so we check underlying dict directly for state
    # But get() is the public API.
    # If race happened, we might see -1 or missing key when it should be present
    # We relax check: ensure we didn't lose data permanently
    
    with cache._lock:
        exists = "target" in cache._cache
        
    assert exists, "Key was incorrectly deleted by concurrent expiry check despite update"
EOF

# 6. Record MD5 of tests to prevent modification
find "$PROJECT_DIR/tests" -type f -exec md5sum {} \; | sort > /tmp/tests_checksum.md5

# 7. Record start time
date +%s > /tmp/task_start_time.txt

# 8. Start PyCharm
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 nohup /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /tmp/pycharm_run.log 2>&1 &"

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "PyCharm"; then
        echo "PyCharm window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "PyCharm" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 5
DISPLAY=:1 wmctrl -r "concurrent_cache" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="