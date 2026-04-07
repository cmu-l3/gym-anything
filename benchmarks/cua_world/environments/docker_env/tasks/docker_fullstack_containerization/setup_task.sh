#!/bin/bash
set -e
echo "=== Setting up Docker Full-Stack Containerization Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done
        return 1
    }
fi
wait_for_docker

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# Cleanup previous state
echo "Cleaning previous state..."
cd /tmp  # ensure we're not in a directory that will be deleted
docker compose -f /home/ga/projects/acme-inventory/docker-compose.yml down -v 2>/dev/null || true
docker rm -f $(docker ps -aq --filter "name=acme") 2>/dev/null || true
docker volume rm $(docker volume ls -q --filter "name=acme") 2>/dev/null || true
rm -rf /home/ga/projects/acme-inventory
rm -f /tmp/task_result.json /tmp/fullstack_result.json
mkdir -p /home/ga/Desktop

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Create project directory structure
PROJECT_DIR="/home/ga/projects/acme-inventory"
mkdir -p "$PROJECT_DIR/api/routes"
mkdir -p "$PROJECT_DIR/worker"
mkdir -p "$PROJECT_DIR/db"
mkdir -p "$PROJECT_DIR/nginx"

# ============================================================
# README.md
# ============================================================
cat > "$PROJECT_DIR/README.md" << 'EOF'
# ACME Inventory Management Platform

A multi-component inventory management system for tracking products across warehouses and processing orders.

## Architecture

The platform consists of five components:

1. **Flask REST API** (`api/`) - Main application serving product, inventory, and order endpoints
2. **PostgreSQL Database** (`db/`) - Persistent storage with schema and seed data
3. **Redis** - Message broker for Celery task queue and caching
4. **Celery Worker** (`worker/`) - Background task processor for async order processing
5. **Nginx** (`nginx/`) - Reverse proxy and load balancer (configuration to be created)

## Project Structure

```
acme-inventory/
├── api/
│   ├── __init__.py          # Flask app factory
│   ├── config.py            # Configuration (env vars)
│   ├── models.py            # Database models
│   ├── requirements.txt     # Python dependencies
│   └── routes/
│       ├── __init__.py      # Blueprint registration
│       ├── products.py      # GET /api/products
│       ├── inventory.py     # GET /api/inventory
│       └── orders.py        # GET/POST /api/orders
├── worker/
│   ├── celery_app.py        # Celery configuration
│   ├── tasks.py             # Background tasks
│   └── requirements.txt     # Worker dependencies
├── db/
│   ├── schema.sql           # Table definitions
│   └── data.sql             # Seed data
├── nginx/                   # Nginx config (to be created)
├── wsgi.py                  # Gunicorn entry point
└── run.py                   # Development server
```

## Configuration

The application uses environment variables for configuration:

- `DB_HOST` - PostgreSQL host (default: localhost)
- `DB_PORT` - PostgreSQL port (default: 5432)
- `DB_NAME` - Database name (default: acme_inventory)
- `DB_USER` - Database user (default: acme)
- `DB_PASSWORD` - Database password (default: acme_secret_2024)
- `REDIS_URL` - Redis connection URL (default: redis://localhost:6379/0)
- `CELERY_BROKER_URL` - Celery broker URL (default: redis://localhost:6379/1)

## API Endpoints

- `GET /health` - Health check
- `GET /api/products` - List all products
- `GET /api/inventory` - List inventory across all warehouses
- `GET /api/orders` - List all orders
- `POST /api/orders` - Create a new order (triggers async processing)
EOF

# ============================================================
# api/__init__.py
# ============================================================
cat > "$PROJECT_DIR/api/__init__.py" << 'PYEOF'
from flask import Flask
from .config import DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD, REDIS_URL


def create_app():
    app = Flask(__name__)

    app.config['DB_HOST'] = DB_HOST
    app.config['DB_PORT'] = DB_PORT
    app.config['DB_NAME'] = DB_NAME
    app.config['DB_USER'] = DB_USER
    app.config['DB_PASSWORD'] = DB_PASSWORD
    app.config['REDIS_URL'] = REDIS_URL

    from .routes.products import products_bp
    from .routes.inventory import inventory_bp
    from .routes.orders import orders_bp

    app.register_blueprint(products_bp)
    app.register_blueprint(inventory_bp)
    app.register_blueprint(orders_bp)

    @app.route('/health')
    def health():
        return {'status': 'healthy'}, 200

    return app
PYEOF

# ============================================================
# api/config.py
# ============================================================
cat > "$PROJECT_DIR/api/config.py" << 'PYEOF'
import os

DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_PORT = os.environ.get('DB_PORT', '5432')
DB_NAME = os.environ.get('DB_NAME', 'acme_inventory')
DB_USER = os.environ.get('DB_USER', 'acme')
DB_PASSWORD = os.environ.get('DB_PASSWORD', 'acme_secret_2024')
REDIS_URL = os.environ.get('REDIS_URL', 'redis://localhost:6379/0')
CELERY_BROKER_URL = os.environ.get('CELERY_BROKER_URL', 'redis://localhost:6379/1')


def get_db_connection_string():
    return f"host={DB_HOST} port={DB_PORT} dbname={DB_NAME} user={DB_USER} password={DB_PASSWORD}"
PYEOF

# ============================================================
# api/models.py
# ============================================================
cat > "$PROJECT_DIR/api/models.py" << 'PYEOF'
import psycopg2
from flask import current_app


def get_db_connection():
    return psycopg2.connect(
        host=current_app.config['DB_HOST'],
        port=current_app.config['DB_PORT'],
        dbname=current_app.config['DB_NAME'],
        user=current_app.config['DB_USER'],
        password=current_app.config['DB_PASSWORD']
    )


def get_all_products():
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT id, sku, name, description, price, category, weight
            FROM product ORDER BY id
        """)
        columns = ['id', 'sku', 'name', 'description', 'price', 'category', 'weight']
        products = []
        for row in cur.fetchall():
            product = dict(zip(columns, row))
            product['price'] = float(product['price'])
            product['weight'] = float(product['weight'])
            products.append(product)
        cur.close()
        return products
    finally:
        conn.close()


def get_all_inventory():
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT i.product_id, p.name as product_name, p.sku,
                   i.warehouse_id, w.name as warehouse_name, w.location,
                   i.quantity, i.minimum_stock, i.last_updated
            FROM inventory i
            JOIN product p ON i.product_id = p.id
            JOIN warehouse w ON i.warehouse_id = w.id
            ORDER BY i.product_id, i.warehouse_id
        """)
        columns = ['product_id', 'product_name', 'sku', 'warehouse_id',
                    'warehouse_name', 'location', 'quantity', 'minimum_stock',
                    'last_updated']
        inventory = []
        for row in cur.fetchall():
            entry = dict(zip(columns, row))
            if entry['last_updated']:
                entry['last_updated'] = entry['last_updated'].isoformat()
            inventory.append(entry)
        cur.close()
        return inventory
    finally:
        conn.close()


def get_all_orders():
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT id, product_id, warehouse_id, quantity, status,
                   created_at, updated_at
            FROM order_record ORDER BY id
        """)
        columns = ['id', 'product_id', 'warehouse_id', 'quantity', 'status',
                    'created_at', 'updated_at']
        orders = []
        for row in cur.fetchall():
            order = dict(zip(columns, row))
            if order['created_at']:
                order['created_at'] = order['created_at'].isoformat()
            if order['updated_at']:
                order['updated_at'] = order['updated_at'].isoformat()
            orders.append(order)
        cur.close()
        return orders
    finally:
        conn.close()


def create_order(product_id, quantity, warehouse_id):
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO order_record (product_id, warehouse_id, quantity, status)
            VALUES (%s, %s, %s, 'pending')
            RETURNING id, status, created_at
        """, (product_id, warehouse_id, quantity))
        row = cur.fetchone()
        conn.commit()
        cur.close()
        return {
            'order_id': row[0],
            'product_id': product_id,
            'warehouse_id': warehouse_id,
            'quantity': quantity,
            'status': row[1],
            'created_at': row[2].isoformat() if row[2] else None
        }
    finally:
        conn.close()
PYEOF

# ============================================================
# api/routes/__init__.py
# ============================================================
cat > "$PROJECT_DIR/api/routes/__init__.py" << 'PYEOF'
from .products import products_bp
from .inventory import inventory_bp
from .orders import orders_bp

__all__ = ['products_bp', 'inventory_bp', 'orders_bp']
PYEOF

# ============================================================
# api/routes/products.py
# ============================================================
cat > "$PROJECT_DIR/api/routes/products.py" << 'PYEOF'
from flask import Blueprint, jsonify
from ..models import get_all_products

products_bp = Blueprint('products', __name__)


@products_bp.route('/api/products', methods=['GET'])
def list_products():
    products = get_all_products()
    return jsonify(products), 200
PYEOF

# ============================================================
# api/routes/inventory.py
# ============================================================
cat > "$PROJECT_DIR/api/routes/inventory.py" << 'PYEOF'
from flask import Blueprint, jsonify
from ..models import get_all_inventory

inventory_bp = Blueprint('inventory', __name__)


@inventory_bp.route('/api/inventory', methods=['GET'])
def list_inventory():
    inventory = get_all_inventory()
    return jsonify(inventory), 200
PYEOF

# ============================================================
# api/routes/orders.py
# ============================================================
cat > "$PROJECT_DIR/api/routes/orders.py" << 'PYEOF'
from flask import Blueprint, jsonify, request
from ..models import get_all_orders, create_order
from ..config import CELERY_BROKER_URL
from celery import Celery

orders_bp = Blueprint('orders', __name__)

celery = Celery('tasks', broker=CELERY_BROKER_URL)


@orders_bp.route('/api/orders', methods=['GET'])
def list_orders():
    orders = get_all_orders()
    return jsonify(orders), 200


@orders_bp.route('/api/orders', methods=['POST'])
def create_new_order():
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Request body required'}), 400

    product_id = data.get('product_id')
    quantity = data.get('quantity')
    warehouse_id = data.get('warehouse_id')

    if not all([product_id, quantity, warehouse_id]):
        return jsonify({'error': 'product_id, quantity, and warehouse_id are required'}), 400

    order = create_order(product_id, quantity, warehouse_id)
    celery.send_task('tasks.process_order', args=[order['order_id']])
    return jsonify(order), 201
PYEOF

# ============================================================
# api/requirements.txt
# ============================================================
cat > "$PROJECT_DIR/api/requirements.txt" << 'EOF'
flask==3.0.0
psycopg2-binary==2.9.9
celery==5.3.6
redis==5.0.1
gunicorn==21.2.0
EOF

# ============================================================
# wsgi.py
# ============================================================
cat > "$PROJECT_DIR/wsgi.py" << 'PYEOF'
from api import create_app

app = create_app()
PYEOF

# ============================================================
# run.py
# ============================================================
cat > "$PROJECT_DIR/run.py" << 'PYEOF'
from api import create_app

if __name__ == '__main__':
    app = create_app()
    app.run(host='0.0.0.0', port=5000, debug=True)
PYEOF

# ============================================================
# worker/celery_app.py
# ============================================================
cat > "$PROJECT_DIR/worker/celery_app.py" << 'PYEOF'
import os
from celery import Celery

CELERY_BROKER_URL = os.environ.get('CELERY_BROKER_URL', 'redis://localhost:6379/1')

celery = Celery('tasks', broker=CELERY_BROKER_URL)
celery.conf.update(
    task_serializer='json',
    accept_content=['json'],
    result_serializer='json',
    timezone='UTC',
    enable_utc=True,
)
PYEOF

# ============================================================
# worker/tasks.py
# ============================================================
cat > "$PROJECT_DIR/worker/tasks.py" << 'PYEOF'
import os
import time
import psycopg2
from celery_app import celery

DATABASE_URL = os.environ.get(
    'DATABASE_URL',
    'postgresql://acme:acme_secret_2024@localhost:5432/acme_inventory'
)


def get_db_connection():
    return psycopg2.connect(DATABASE_URL)


@celery.task(name='tasks.process_order')
def process_order(order_id):
    time.sleep(1)
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT product_id, warehouse_id, quantity FROM order_record WHERE id = %s",
            (order_id,)
        )
        row = cur.fetchone()
        if not row:
            return {'error': 'Order not found'}

        product_id, warehouse_id, quantity = row

        cur.execute(
            "UPDATE inventory SET quantity = quantity - %s, last_updated = NOW() "
            "WHERE product_id = %s AND warehouse_id = %s",
            (quantity, product_id, warehouse_id)
        )

        cur.execute(
            "UPDATE order_record SET status = 'completed', updated_at = NOW() "
            "WHERE id = %s",
            (order_id,)
        )

        conn.commit()
        cur.close()
        return {'order_id': order_id, 'status': 'completed'}
    except Exception as e:
        conn.rollback()
        cur2 = conn.cursor()
        cur2.execute(
            "UPDATE order_record SET status = 'failed', updated_at = NOW() WHERE id = %s",
            (order_id,)
        )
        conn.commit()
        cur2.close()
        return {'order_id': order_id, 'status': 'failed', 'error': str(e)}
    finally:
        conn.close()
PYEOF

# ============================================================
# worker/requirements.txt
# ============================================================
cat > "$PROJECT_DIR/worker/requirements.txt" << 'EOF'
celery==5.3.6
redis==5.0.1
psycopg2-binary==2.9.9
EOF

# ============================================================
# db/schema.sql
# ============================================================
cat > "$PROJECT_DIR/db/schema.sql" << 'EOF'
-- ACME Inventory Management Platform - Database Schema

CREATE TABLE IF NOT EXISTS product (
    id SERIAL PRIMARY KEY,
    sku VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    price NUMERIC(10,2) NOT NULL,
    category VARCHAR(50) NOT NULL,
    weight NUMERIC(8,2) DEFAULT 0.0
);

CREATE TABLE IF NOT EXISTS warehouse (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    location VARCHAR(200) NOT NULL,
    capacity INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS inventory (
    product_id INTEGER REFERENCES product(id),
    warehouse_id INTEGER REFERENCES warehouse(id),
    quantity INTEGER NOT NULL DEFAULT 0,
    minimum_stock INTEGER NOT NULL DEFAULT 10,
    last_updated TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (product_id, warehouse_id)
);

CREATE TABLE IF NOT EXISTS order_record (
    id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES product(id),
    warehouse_id INTEGER REFERENCES warehouse(id),
    quantity INTEGER NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP
);
EOF

# ============================================================
# db/data.sql
# ============================================================
cat > "$PROJECT_DIR/db/data.sql" << 'EOF'
-- ACME Inventory Management Platform - Seed Data

-- Warehouses:
INSERT INTO warehouse (id, name, location, capacity) VALUES
(1, 'West Coast Distribution Center', 'Portland, OR', 10000),
(2, 'East Coast Fulfillment Hub', 'Newark, NJ', 8000),
(3, 'Central Processing Facility', 'Dallas, TX', 12000);

-- Products:
INSERT INTO product (id, sku, name, description, price, category, weight) VALUES
(1, 'ELEC-001', 'Wireless Ergonomic Mouse', 'Bluetooth ergonomic vertical mouse with adjustable DPI', 29.99, 'Electronics', 0.15),
(2, 'ELEC-002', 'Mechanical Keyboard TKL', 'Tenkeyless mechanical keyboard with Cherry MX switches', 89.99, 'Electronics', 0.85),
(3, 'ELEC-003', 'USB-C Multiport Hub', '7-in-1 USB-C hub with HDMI, USB-A, SD card reader', 45.99, 'Electronics', 0.12),
(4, 'ELEC-004', '1080p Webcam with Microphone', 'Full HD webcam with built-in noise-canceling microphone', 54.99, 'Electronics', 0.18),
(5, 'ELEC-005', 'Adjustable Monitor Riser Stand', 'Aluminum monitor stand with height adjustment and USB ports', 39.99, 'Electronics', 1.20),
(6, 'OFFC-001', 'LED Desk Lamp with Clamp', 'Adjustable LED desk lamp with clamp mount and dimmer', 34.99, 'Office', 0.95),
(7, 'OFFC-002', 'Ergonomic Office Chair', 'Mesh back ergonomic chair with lumbar support and armrests', 299.99, 'Office', 15.00),
(8, 'OFFC-003', 'Anti-Fatigue Standing Desk Mat', 'Cushioned standing desk mat with beveled edges', 49.99, 'Office', 2.50),
(9, 'OFFC-004', 'Dry Erase Whiteboard Markers 12pk', 'Set of 12 low-odor dry erase markers in assorted colors', 12.99, 'Office', 0.35),
(10, 'OFFC-005', 'Cross-Cut Paper Shredder', '10-sheet cross-cut shredder with 5-gallon bin', 89.99, 'Office', 6.80),
(11, 'SUPP-001', 'Premium A4 Copy Paper 5000-Sheet', 'Bright white 80gsm copy paper, 10 reams of 500 sheets', 42.99, 'Supplies', 25.00),
(12, 'SUPP-002', 'Ink Cartridge Black XL', 'High-yield black ink cartridge, compatible with HP printers', 24.99, 'Supplies', 0.08),
(13, 'SUPP-003', 'Ink Cartridge Tri-Color', 'Tri-color ink cartridge for HP inkjet printers', 34.99, 'Supplies', 0.08),
(14, 'SUPP-004', 'Binder Clips Assorted 100ct', 'Assorted size binder clips in a reusable tub', 8.99, 'Supplies', 0.60),
(15, 'SUPP-005', 'Manila File Folders 25pk', 'Letter-size manila file folders, 1/3-cut tabs', 14.99, 'Supplies', 0.45),
(16, 'TECH-001', 'Portable External SSD 1TB', 'USB 3.2 portable SSD with 1050MB/s read speed', 79.99, 'Tech', 0.10),
(17, 'TECH-002', 'Universal Laptop Docking Station', 'USB-C docking station with dual HDMI and ethernet', 149.99, 'Tech', 0.45),
(18, 'TECH-003', 'Active Noise-Canceling Headphones', 'Over-ear ANC headphones with 30-hour battery', 199.99, 'Tech', 0.28),
(19, 'TECH-004', 'Braided HDMI 2.1 Cable 6ft', 'High-speed braided HDMI cable supporting 4K@120Hz', 9.99, 'Tech', 0.15),
(20, 'TECH-005', 'Surge Protector Power Strip 12-Outlet', '12-outlet surge protector with USB-A and USB-C ports', 24.99, 'Tech', 0.90),
(21, 'ACCS-001', 'Cable Management Kit', 'Desk cable management kit with clips, ties, and sleeves', 19.99, 'Accessories', 0.30),
(22, 'ACCS-002', 'Bamboo Desk Organizer', 'Multi-compartment bamboo desk organizer with drawer', 27.99, 'Accessories', 1.10),
(23, 'ACCS-003', 'Extended Gaming Mouse Pad XL', 'Extra-large mouse pad with stitched edges, 900x400mm', 15.99, 'Accessories', 0.40),
(24, 'ACCS-004', 'Screen Cleaning Kit', 'Screen cleaning spray with microfiber cloth', 11.99, 'Accessories', 0.20),
(25, 'ACCS-005', 'Portable USB-C Phone Charger 20000mAh', 'High-capacity power bank with dual USB-C PD output', 29.99, 'Accessories', 0.35);

-- Inventory (25 products x 3 warehouses = 75 rows):
INSERT INTO inventory (product_id, warehouse_id, quantity, minimum_stock, last_updated) VALUES
(1,  1, 342, 50, NOW()),
(1,  2, 287, 50, NOW()),
(1,  3, 419, 50, NOW()),
(2,  1, 156, 30, NOW()),
(2,  2, 203, 30, NOW()),
(2,  3, 178, 30, NOW()),
(3,  1, 489, 60, NOW()),
(3,  2, 334, 60, NOW()),
(3,  3, 512, 60, NOW()),
(4,  1, 267, 40, NOW()),
(4,  2, 198, 40, NOW()),
(4,  3, 356, 40, NOW()),
(5,  1, 145, 25, NOW()),
(5,  2, 112, 25, NOW()),
(5,  3, 189, 25, NOW()),
(6,  1, 223, 35, NOW()),
(6,  2, 178, 35, NOW()),
(6,  3, 301, 35, NOW()),
(7,  1, 67, 15, NOW()),
(7,  2, 45, 15, NOW()),
(7,  3, 89, 15, NOW()),
(8,  1, 134, 20, NOW()),
(8,  2, 98, 20, NOW()),
(8,  3, 167, 20, NOW()),
(9,  1, 567, 100, NOW()),
(9,  2, 423, 100, NOW()),
(9,  3, 634, 100, NOW()),
(10, 1, 78, 15, NOW()),
(10, 2, 56, 15, NOW()),
(10, 3, 92, 15, NOW()),
(11, 1, 234, 50, NOW()),
(11, 2, 189, 50, NOW()),
(11, 3, 312, 50, NOW()),
(12, 1, 445, 80, NOW()),
(12, 2, 367, 80, NOW()),
(12, 3, 523, 80, NOW()),
(13, 1, 398, 70, NOW()),
(13, 2, 312, 70, NOW()),
(13, 3, 467, 70, NOW()),
(14, 1, 678, 100, NOW()),
(14, 2, 534, 100, NOW()),
(14, 3, 756, 100, NOW()),
(15, 1, 345, 50, NOW()),
(15, 2, 278, 50, NOW()),
(15, 3, 412, 50, NOW()),
(16, 1, 189, 30, NOW()),
(16, 2, 145, 30, NOW()),
(16, 3, 234, 30, NOW()),
(17, 1, 98, 20, NOW()),
(17, 2, 67, 20, NOW()),
(17, 3, 123, 20, NOW()),
(18, 1, 134, 25, NOW()),
(18, 2, 89, 25, NOW()),
(18, 3, 178, 25, NOW()),
(19, 1, 723, 100, NOW()),
(19, 2, 589, 100, NOW()),
(19, 3, 834, 100, NOW()),
(20, 1, 267, 40, NOW()),
(20, 2, 198, 40, NOW()),
(20, 3, 334, 40, NOW()),
(21, 1, 356, 50, NOW()),
(21, 2, 289, 50, NOW()),
(21, 3, 423, 50, NOW()),
(22, 1, 178, 30, NOW()),
(22, 2, 134, 30, NOW()),
(22, 3, 212, 30, NOW()),
(23, 1, 445, 60, NOW()),
(23, 2, 367, 60, NOW()),
(23, 3, 523, 60, NOW()),
(24, 1, 534, 80, NOW()),
(24, 2, 423, 80, NOW()),
(24, 3, 612, 80, NOW()),
(25, 1, 289, 40, NOW()),
(25, 2, 234, 40, NOW()),
(25, 3, 367, 40, NOW());

SELECT setval('product_id_seq', 25);
SELECT setval('warehouse_id_seq', 3);
EOF

# ============================================================
# Desktop shortcut and final setup
# ============================================================
cat > /home/ga/Desktop/ACME_Inventory_Task.txt << 'EOF'
ACME Inventory Management Platform - Containerization Task

Project location: ~/projects/acme-inventory/

Your task: Containerize and deploy this application using Docker.
Read the README.md in the project directory for architecture details.

Required components:
- Dockerfiles for API and Worker
- docker-compose.yml for orchestration
- Nginx configuration for reverse proxy
- Application accessible at http://localhost:8080
EOF

chmod -R 755 "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR" 2>/dev/null || true
chown -R ga:ga /home/ga/Desktop 2>/dev/null || true

take_screenshot /tmp/task_setup_complete.png

echo "=== Setup complete ==="
echo "Project directory: $PROJECT_DIR"
echo "Source files: $(find $PROJECT_DIR -type f | wc -l) files created"
ls -la "$PROJECT_DIR/"
