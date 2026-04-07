#!/bin/bash
set -e
echo "=== Setting up optimize_inventory_queries task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/inventory_system"
mkdir -p "$PROJECT_DIR/inventory"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/data"

# Record start time for timestamp validation
date +%s > /tmp/task_start_time.txt

# --- 1. Define Models ---
cat > "$PROJECT_DIR/inventory/models.py" << 'EOF'
from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime
from sqlalchemy.orm import relationship, declarative_base

Base = declarative_base()

class Warehouse(Base):
    __tablename__ = 'warehouses'
    id = Column(Integer, primary_key=True)
    name = Column(String)
    location = Column(String)
    
    products = relationship("Product", back_populates="warehouse")

class Product(Base):
    __tablename__ = 'products'
    id = Column(Integer, primary_key=True)
    sku = Column(String, unique=True)
    name = Column(String)
    price = Column(Float)
    warehouse_id = Column(Integer, ForeignKey('warehouses.id'))
    
    warehouse = relationship("Warehouse", back_populates="products")
    stock = relationship("Stock", uselist=False, back_populates="product")
    movements = relationship("Movement", back_populates="product")

class Stock(Base):
    __tablename__ = 'stock'
    id = Column(Integer, primary_key=True)
    product_id = Column(Integer, ForeignKey('products.id'))
    quantity = Column(Integer)
    
    product = relationship("Product", back_populates="stock")

class Movement(Base):
    __tablename__ = 'movements'
    id = Column(Integer, primary_key=True)
    product_id = Column(Integer, ForeignKey('products.id'))
    date = Column(DateTime)
    quantity_change = Column(Integer)
    type = Column(String) # 'IN', 'OUT'
    
    product = relationship("Product", back_populates="movements")
EOF

# --- 2. Database Setup ---
cat > "$PROJECT_DIR/inventory/database.py" << 'EOF'
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from inventory.models import Base
import os

# Use absolute path to ensure tests find it regardless of CWD
DB_PATH = "sqlite:////home/ga/PycharmProjects/inventory_system/data/inventory.db"
engine = create_engine(DB_PATH)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def init_db():
    Base.metadata.create_all(bind=engine)
EOF

# --- 3. Data Generator ---
cat > "$PROJECT_DIR/inventory/generate_data.py" << 'EOF'
import os
import random
import sys
from datetime import datetime, timedelta
from faker import Faker
from inventory.models import Base, Product, Warehouse, Stock, Movement
from inventory.database import engine, SessionLocal, init_db

fake = Faker()
# Set seed to ensure reproducible data for verification if needed
Faker.seed(42)
random.seed(42)

def generate():
    db_file = "/home/ga/PycharmProjects/inventory_system/data/inventory.db"
    if os.path.exists(db_file):
        os.remove(db_file)
    
    init_db()
    session = SessionLocal()
    
    print("Generating Warehouses...")
    warehouses = []
    for _ in range(5):
        w = Warehouse(name=fake.company(), location=fake.city())
        warehouses.append(w)
        session.add(w)
    session.commit()
    
    print("Generating Products & Stock...")
    # Create enough data to make N+1 painful (~500 products)
    for i in range(500):
        w = random.choice(warehouses)
        p = Product(
            sku=fake.ean13(),
            name=fake.bs().title(),
            price=round(random.uniform(10.0, 500.0), 2),
            warehouse_id=w.id
        )
        session.add(p)
        session.flush() # get ID
        
        # Stock
        s = Stock(product_id=p.id, quantity=random.randint(0, 1000))
        session.add(s)
        
        # Movements (0 to 10 per product)
        for _ in range(random.randint(0, 10)):
            m_date = fake.date_time_between(start_date='-1y', end_date='now')
            m = Movement(
                product_id=p.id,
                date=m_date,
                quantity_change=random.randint(-50, 50),
                type=random.choice(['IN', 'OUT'])
            )
            session.add(m)
            
    session.commit()
    print("Data generation complete.")

if __name__ == "__main__":
    generate()
EOF

# --- 4. The Report Code (INEFFICIENT) ---
cat > "$PROJECT_DIR/inventory/report.py" << 'EOF'
from inventory.models import Product, Movement, Stock, Warehouse
from sqlalchemy.orm import Session

def generate_valuation_report(session: Session):
    """
    Generates a report of all products, their current value, warehouse location,
    and the date of their last movement.
    
    Returns a list of dicts:
    [
        {
            "sku": "...",
            "name": "...",
            "warehouse": "...",
            "quantity": 10,
            "total_value": 500.0,
            "last_movement": datetime(...) or None
        },
        ...
    ]
    """
    # PROBLEM 1: This fetches only products initially
    products = session.query(Product).all()
    
    report = []
    
    for p in products:
        # PROBLEM 2: Lazy loading Warehouse (N queries)
        wh_name = p.warehouse.name if p.warehouse else "Unknown"
        
        # PROBLEM 3: Lazy loading Stock (N queries)
        qty = p.stock.quantity if p.stock else 0
        
        # PROBLEM 4: Fetching ALL movements just to find the latest (N queries)
        # Inefficient Python-side logic
        movements = session.query(Movement).filter(Movement.product_id == p.id).all()
        
        last_date = None
        if movements:
            # Sort in Python
            movements.sort(key=lambda x: x.date, reverse=True)
            last_date = movements[0].date
            
        report.append({
            "sku": p.sku,
            "name": p.name,
            "warehouse": wh_name,
            "quantity": qty,
            "total_value": round(qty * p.price, 2),
            "last_movement": last_date
        })
        
    return report
EOF

# --- 5. Tests ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
from inventory.database import SessionLocal

@pytest.fixture(scope="session")
def db_session():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()
EOF

cat > "$PROJECT_DIR/tests/test_functional.py" << 'EOF'
import pytest
from inventory.report import generate_valuation_report

def test_report_structure_and_data(db_session):
    """Verifies that the report returns correct data structure and non-empty results."""
    report = generate_valuation_report(db_session)
    
    assert len(report) == 500, "Report should contain all 500 products"
    
    first_item = report[0]
    required_keys = {"sku", "name", "warehouse", "quantity", "total_value", "last_movement"}
    assert required_keys.issubset(first_item.keys()), f"Missing keys in report. Found: {first_item.keys()}"
    
    # Check data consistency
    if first_item['quantity'] > 0 and first_item['total_value'] == 0:
        pytest.fail("Total value is 0 but quantity is > 0")

    assert isinstance(first_item['warehouse'], str)
    assert len(first_item['warehouse']) > 0
EOF

cat > "$PROJECT_DIR/tests/test_performance.py" << 'EOF'
import pytest
from sqlalchemy import event
from inventory.report import generate_valuation_report

class QueryCounter:
    def __init__(self):
        self.count = 0
        
    def __call__(self, conn, cursor, statement, parameters, context, executemany):
        self.count += 1

def test_query_count(db_session):
    """
    Strict performance test. 
    Original implementation: ~2500 queries
    Optimized target: < 10 queries
    """
    counter = QueryCounter()
    event.listen(db_session.bind, "before_cursor_execute", counter)
    
    try:
        report = generate_valuation_report(db_session)
    finally:
        event.remove(db_session.bind, "before_cursor_execute", counter)
        
    print(f"\nTotal Queries Executed: {counter.count}")
    
    if counter.count > 1000:
        pytest.fail(f"CRITICAL: Query count is {counter.count} (Expected < 10). N+1 problem detected!")
        
    if counter.count > 10:
        pytest.fail(f"PERFORMANCE: Query count is {counter.count} (Expected < 10). Aggregation not fully optimized.")
EOF

# --- 6. Install Dependencies & Generate Data ---
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
sqlalchemy
faker
pytest
EOF

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# Install packages
su - ga -c "pip3 install -r $PROJECT_DIR/requirements.txt"

# Generate data
su - ga -c "PYTHONPATH=$PROJECT_DIR python3 $PROJECT_DIR/inventory/generate_data.py"

# --- 7. Launch PyCharm ---
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /tmp/pycharm_startup.log 2>&1 &"

# Wait for PyCharm
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "inventory_system"; then
        break
    fi
    sleep 2
done

# Maximize and dismiss dialogs
DISPLAY=:1 wmctrl -r "inventory_system" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="