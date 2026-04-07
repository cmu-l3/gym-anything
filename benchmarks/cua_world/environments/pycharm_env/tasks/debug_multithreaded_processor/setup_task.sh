#!/bin/bash
set -e
echo "=== Setting up debug_multithreaded_processor task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/transaction_engine"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/app"
mkdir -p "$PROJECT_DIR/data"
mkdir -p "$PROJECT_DIR/tests"

# --- 1. app/account.py (BUGGY: Missing lock usage) ---
cat > "$PROJECT_DIR/app/account.py" << 'PYEOF'
import threading
import time

class Account:
    def __init__(self, account_id: str, initial_balance: float = 0.0):
        self.id = account_id
        self.balance = initial_balance
        # Lock is provided but NOT used in update_balance (Bug 1: Race Condition)
        self._lock = threading.Lock()

    def deposit(self, amount: float):
        """Add funds to the account."""
        self._update_balance(amount)

    def withdraw(self, amount: float):
        """Remove funds from the account."""
        self._update_balance(-amount)

    def _update_balance(self, amount: float):
        """Internal method to update balance.
        
        CRITICAL BUG: This method is not thread-safe.
        When multiple threads call this simultaneously, 'Lost Updates' occur.
        """
        # Simulate a tiny processing delay to widen the race condition window
        # This makes the bug reproducible even with the GIL
        current = self.balance
        time.sleep(0.0001) 
        self.balance = current + amount

    def get_balance(self) -> float:
        return self.balance
PYEOF

# --- 2. app/transfer.py (BUGGY: Naive lock ordering) ---
cat > "$PROJECT_DIR/app/transfer.py" << 'PYEOF'
import threading
import time
from app.account import Account

def transfer_funds(from_acc: Account, to_acc: Account, amount: float):
    """
    Transfer funds between two accounts safely?
    
    CRITICAL BUG: This acquires locks in the order arguments are passed.
    If Thread 1 calls transfer(A, B) and Thread 2 calls transfer(B, A),
    a DEADLOCK will occur.
    """
    # Naive locking - prone to deadlock
    with from_acc._lock:
        # Simulate processing time holding the first lock
        time.sleep(0.001)
        
        with to_acc._lock:
            if from_acc.get_balance() >= amount:
                from_acc.withdraw(amount)
                to_acc.deposit(amount)
                return True
            return False
PYEOF

# --- 3. app/processor.py (Engine) ---
cat > "$PROJECT_DIR/app/processor.py" << 'PYEOF'
import csv
import threading
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, List
from app.account import Account
from app.transfer import transfer_funds

class TransactionEngine:
    def __init__(self):
        self.accounts: Dict[str, Account] = {}
        
    def get_or_create_account(self, acc_id: str) -> Account:
        if acc_id not in self.accounts:
            self.accounts[acc_id] = Account(acc_id, 1000.0) # Start with $1000
        return self.accounts[acc_id]

    def process_csv(self, filepath: str, max_workers: int = 10):
        """Process a CSV of transactions using a thread pool."""
        transactions = []
        
        # Read all transactions first
        with open(filepath, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                transactions.append(row)
                
        # Initialize accounts involved
        for row in transactions:
            self.get_or_create_account(row['source_acc'])
            self.get_or_create_account(row['target_acc'])
            
        # Execute in parallel
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = []
            for row in transactions:
                source = self.accounts[row['source_acc']]
                target = self.accounts[row['target_acc']]
                amount = float(row['amount'])
                
                futures.append(
                    executor.submit(transfer_funds, source, target, amount)
                )
            
            # Wait for all to complete
            for f in futures:
                f.result()
PYEOF

# --- 4. tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
from app.account import Account

@pytest.fixture
def accounts():
    return {
        "A": Account("A", 1000.0),
        "B": Account("B", 1000.0),
        "C": Account("C", 1000.0)
    }
PYEOF

# --- 5. tests/test_balances.py (Detects Race Condition) ---
cat > "$PROJECT_DIR/tests/test_balances.py" << 'PYEOF'
import threading
from app.account import Account

def test_race_condition_deposit():
    """
    Test that concurrent deposits don't lose data.
    If 50 threads deposit 10.0 each, balance should increase by 500.0.
    With the bug, it will be much less.
    """
    acc = Account("TEST", 0.0)
    threads = []
    
    def worker():
        for _ in range(10):
            acc.deposit(10.0)
            
    # Launch 10 threads, each doing 10 deposits of 10.0
    # Expected total: 10 * 10 * 10.0 = 1000.0
    for _ in range(10):
        t = threading.Thread(target=worker)
        threads.append(t)
        t.start()
        
    for t in threads:
        t.join()
        
    final_balance = acc.get_balance()
    # In a race condition, final_balance will be < 1000.0
    assert final_balance == 1000.0, f"Race condition detected! Expected 1000.0, got {final_balance}"
PYEOF

# --- 6. tests/test_stress.py (Detects Deadlock) ---
cat > "$PROJECT_DIR/tests/test_stress.py" << 'PYEOF'
import threading
import time
import pytest
from app.account import Account
from app.transfer import transfer_funds

def test_deadlock_scenario():
    """
    Stress test that deliberately causes lock contention order mismatches.
    Thread 1: A -> B
    Thread 2: B -> A
    
    If the deadlock is fixed (e.g. by lock ordering), this test finishes.
    If not, it hangs (and pytest-timeout or the verifier kills it).
    """
    acc_a = Account("A", 1000.0)
    acc_b = Account("B", 1000.0)
    
    iterations = 100
    
    def transfer_a_to_b():
        for _ in range(iterations):
            transfer_funds(acc_a, acc_b, 1.0)
            
    def transfer_b_to_a():
        for _ in range(iterations):
            transfer_funds(acc_b, acc_a, 1.0)
            
    t1 = threading.Thread(target=transfer_a_to_b)
    t2 = threading.Thread(target=transfer_b_to_a)
    
    t1.start()
    t2.start()
    
    t1.join(timeout=5.0)
    t2.join(timeout=5.0)
    
    if t1.is_alive() or t2.is_alive():
        pytest.fail("Deadlock detected! Threads failed to join within timeout.")
PYEOF

# --- 7. Generate Data ---
cat > "$PROJECT_DIR/generate_data.py" << 'PYEOF'
import csv
import random

accounts = [f"ACC_{i}" for i in range(1, 21)] # 20 accounts
records = []

# Generate 2000 transactions
for i in range(2000):
    src, tgt = random.sample(accounts, 2)
    amount = round(random.uniform(10.0, 500.0), 2)
    records.append({
        "txn_id": f"TXN_{i}",
        "source_acc": src,
        "target_acc": tgt,
        "amount": amount
    })

with open("data/settlement_20231027.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["txn_id", "source_acc", "target_acc", "amount"])
    writer.writeheader()
    writer.writerows(records)
PYEOF

cd "$PROJECT_DIR"
python3 generate_data.py
rm generate_data.py

# --- 8. requirements.txt ---
echo "pytest" > "$PROJECT_DIR/requirements.txt"

# Record timestamp
date +%s > /tmp/task_start_time.txt

# Open PyCharm
echo "Opening PyCharm..."
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /dev/null 2>&1 &"

# Wait for PyCharm
wait_for_pycharm 120
focus_pycharm_window
dismiss_dialogs 3
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="