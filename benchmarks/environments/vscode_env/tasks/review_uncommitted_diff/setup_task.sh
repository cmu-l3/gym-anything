#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Review Uncommitted Diff Task ==="

WORKSPACE_DIR="/home/ga/workspace"
REPO_DIR="$WORKSPACE_DIR/api_service"

# Clean up any existing directory
sudo rm -rf "$REPO_DIR"
sudo -u ga mkdir -p "$REPO_DIR"

# Initialize Git repository
cd "$REPO_DIR"
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"

echo "Creating FastAPI project structure..."

# Create directory structure
sudo -u ga mkdir -p "$REPO_DIR/api/routes"
sudo -u ga mkdir -p "$REPO_DIR/api/services"
sudo -u ga mkdir -p "$REPO_DIR/api/utils"
sudo -u ga mkdir -p "$REPO_DIR/tests"

# Create __init__.py files
touch "$REPO_DIR/api/__init__.py"
touch "$REPO_DIR/api/routes/__init__.py"
touch "$REPO_DIR/api/services/__init__.py"
touch "$REPO_DIR/api/utils/__init__.py"
touch "$REPO_DIR/tests/__init__.py"

# Create initial orders.py (without bug fix, without debug code)
cat > "$REPO_DIR/api/routes/orders.py" << 'EOF'
from fastapi import APIRouter, HTTPException
import asyncio

router = APIRouter()

@router.post("/orders/")
async def create_order(order_data: dict):
    """Create a new order"""
    order_id = order_data.get("id")
    
    if not order_id:
        raise HTTPException(status_code=400, detail="Order ID required")
    
    # Process order...
    result = await process_payment(order_data)
    
    return {"status": "success", "order_id": order_id}


async def process_payment(order_data: dict):
    """Process payment for order"""
    # Payment processing logic
    await asyncio.sleep(0.1)
    return {"payment_status": "completed"}
EOF

# Create initial payment.py (without fix, without debug code)
cat > "$REPO_DIR/api/services/payment.py" << 'EOF'
from typing import Dict, Any

class PaymentService:
    """Service for handling payment operations"""
    
    def validate_payment(self, amount: float, currency: str) -> bool:
        """Validate payment details"""
        if amount <= 0:
            return False
        
        allowed_currencies = ["USD", "EUR", "GBP"]
        if currency not in allowed_currencies:
            return False
        
        return True
    
    def process_transaction(self, payment_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process payment transaction"""
        amount = payment_data.get("amount", 0)
        currency = payment_data.get("currency", "USD")
        
        if not self.validate_payment(amount, currency):
            raise ValueError("Invalid payment details")
        
        return {
            "transaction_id": "txn_12345",
            "status": "success",
            "amount": amount
        }
EOF

# Create initial logger.py (without improvements)
cat > "$REPO_DIR/api/utils/logger.py" << 'EOF'
import logging
import sys

def setup_logger(name: str) -> logging.Logger:
    """Setup basic logger"""
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    
    handler = logging.StreamHandler(sys.stdout)
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    
    return logger
EOF

# Create initial test file (without new test)
cat > "$REPO_DIR/tests/test_orders.py" << 'EOF'
import pytest
from api.routes.orders import create_order

@pytest.mark.asyncio
async def test_create_order_basic():
    """Test basic order creation"""
    order_data = {"id": "order_123", "items": ["item1"]}
    result = await create_order(order_data)
    assert result["status"] == "success"
    assert result["order_id"] == "order_123"


@pytest.mark.asyncio
async def test_create_order_missing_id():
    """Test order creation without ID"""
    order_data = {"items": ["item1"]}
    with pytest.raises(Exception):
        await create_order(order_data)
EOF

# Create requirements.txt
cat > "$REPO_DIR/requirements.txt" << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
pytest==7.4.3
pytest-asyncio==0.21.1
EOF

# Set ownership
sudo chown -R ga:ga "$REPO_DIR"

# Initial commit
cd "$REPO_DIR"
sudo -u ga git add .
sudo -u ga git commit -m "Initial FastAPI project structure" > /dev/null 2>&1

echo "Creating modified files with debug code..."

# Now create MODIFIED versions with bug fixes AND debug code
# Modified orders.py (with race condition fix + debug prints)
cat > "$REPO_DIR/api/routes/orders.py" << 'EOF'
from fastapi import APIRouter, HTTPException
import asyncio

router = APIRouter()
order_lock = asyncio.Lock()

@router.post("/orders/")
async def create_order(order_data: dict):
    """Create a new order"""
    # FIX: Added lock to prevent race condition
    await order_lock.acquire()
    try:
        order_id = order_data.get("id")
        
        # DEBUG: remove before commit
        print(f"DEBUG: Order ID: {order_id}")
        
        if not order_id:
            raise HTTPException(status_code=400, detail="Order ID required")
        
        # DEBUG: remove before commit
        print("DEBUG: Payment processing started")
        
        # FIX: Added proper error handling
        try:
            result = await process_payment(order_data)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Payment failed: {str(e)}")
        
        return {"status": "success", "order_id": order_id}
    finally:
        order_lock.release()


async def process_payment(order_data: dict):
    """Process payment for order"""
    # Payment processing logic
    await asyncio.sleep(0.1)
    return {"payment_status": "completed"}
EOF

# Modified payment.py (with validation improvement + hardcoded test + debug print)
cat > "$REPO_DIR/api/services/payment.py" << 'EOF'
from typing import Dict, Any

class PaymentService:
    """Service for handling payment operations"""
    
    def validate_payment(self, amount: float, currency: str) -> bool:
        """Validate payment details"""
        if amount <= 0:
            return False
        
        allowed_currencies = ["USD", "EUR", "GBP"]
        if currency not in allowed_currencies:
            return False
        
        return True
    
    def process_transaction(self, payment_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process payment transaction"""
        # TODO: remove test value
        amount = 1.00  # Hardcoded for testing
        currency = payment_data.get("currency", "USD")
        
        # DEBUG: remove before commit
        print(f"DEBUG: Processing payment amount: {amount}")
        
        if not self.validate_payment(amount, currency):
            raise ValueError("Invalid payment details")
        
        # FIX: Added amount validation with better error messages
        if amount > 10000:
            raise ValueError(f"Amount {amount} exceeds maximum transaction limit")
        
        return {
            "transaction_id": "txn_12345",
            "status": "success",
            "amount": amount
        }
EOF

# Modified logger.py (with CLEAN improvements - no debug code)
cat > "$REPO_DIR/api/utils/logger.py" << 'EOF'
import logging
import sys
from typing import Optional

def setup_logger(name: str, request_id: Optional[str] = None) -> logging.Logger:
    """Setup structured logger with request ID tracking"""
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    
    handler = logging.StreamHandler(sys.stdout)
    
    # IMPROVEMENT: Added request_id to log format for better tracing
    if request_id:
        formatter = logging.Formatter(
            f'%(asctime)s - %(name)s - %(levelname)s - [request_id: {request_id}] - %(message)s'
        )
    else:
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    
    return logger
EOF

# Modified test_orders.py (with new test case - CLEAN)
cat > "$REPO_DIR/tests/test_orders.py" << 'EOF'
import pytest
import asyncio
from api.routes.orders import create_order

@pytest.mark.asyncio
async def test_create_order_basic():
    """Test basic order creation"""
    order_data = {"id": "order_123", "items": ["item1"]}
    result = await create_order(order_data)
    assert result["status"] == "success"
    assert result["order_id"] == "order_123"


@pytest.mark.asyncio
async def test_create_order_missing_id():
    """Test order creation without ID"""
    order_data = {"items": ["item1"]}
    with pytest.raises(Exception):
        await create_order(order_data)


@pytest.mark.asyncio
async def test_concurrent_order_creation():
    """Test that concurrent orders don't cause race conditions"""
    order_data_1 = {"id": "order_001", "items": ["item1"]}
    order_data_2 = {"id": "order_002", "items": ["item2"]}
    
    # Create orders concurrently
    results = await asyncio.gather(
        create_order(order_data_1),
        create_order(order_data_2)
    )
    
    assert len(results) == 2
    assert results[0]["status"] == "success"
    assert results[1]["status"] == "success"
EOF

sudo chown -R ga:ga "$REPO_DIR"

# Verify git status shows modifications
cd "$REPO_DIR"
echo "Git status after modifications:"
sudo -u ga git status --short

# Open VSCode with the repository
echo "Opening VSCode with repository..."
su - ga -c "DISPLAY=:1 code '$REPO_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Give VSCode time to load and index files
sleep 3

echo "=== Review Uncommitted Diff Task Setup Complete ==="
echo "📝 Repository: $REPO_DIR"
echo "📝 Modified files:"
echo "   - api/routes/orders.py (race condition fix + debug prints)"
echo "   - api/services/payment.py (validation fix + hardcoded test value)"
echo "   - api/utils/logger.py (clean logging improvements)"
echo "   - tests/test_orders.py (new test case)"
echo ""
echo "📋 Instructions:"
echo "  1. Open Source Control panel (Ctrl+Shift+G)"
echo "  2. Click each file to review diffs"
echo "  3. Remove debug code from orders.py and payment.py"
echo "  4. Verify logger.py and test_orders.py are clean"
echo "  5. Create /home/ga/workspace/REVIEW_SUMMARY.md with review findings"