#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up ecommerce_platform_erd task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any existing output files
rm -f /home/ga/Desktop/shopsphere_erd.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/shopsphere_erd.png 2>/dev/null || true

# Create the ShopSphere e-commerce SQL schema on the Desktop.
# This is a realistic PostgreSQL schema for a mid-size e-commerce platform
# with 14 tables across 3 business domains (Customer, Product, Order).
cat > /home/ga/Desktop/shopsphere_schema.sql << 'SQLEOF'
-- ShopSphere E-Commerce Platform — Database Schema
-- PostgreSQL 16 · Production Release 3.2.1 · 2025-11-15

-- ═══════════════════════════════════════════
--  CUSTOMER DOMAIN
-- ═══════════════════════════════════════════

CREATE TABLE customer (
    customer_id     SERIAL          PRIMARY KEY,
    email           VARCHAR(255)    NOT NULL UNIQUE,
    first_name      VARCHAR(100)    NOT NULL,
    last_name       VARCHAR(100)    NOT NULL,
    phone           VARCHAR(20),
    password_hash   VARCHAR(255)    NOT NULL,
    is_active       BOOLEAN         DEFAULT TRUE,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE address (
    address_id      SERIAL          PRIMARY KEY,
    street_line1    VARCHAR(255)    NOT NULL,
    street_line2    VARCHAR(255),
    city            VARCHAR(100)    NOT NULL,
    state           VARCHAR(100)    NOT NULL,
    postal_code     VARCHAR(20)     NOT NULL,
    country_code    CHAR(2)         NOT NULL DEFAULT 'US'
);

CREATE TABLE customer_address (
    customer_id     INTEGER         NOT NULL REFERENCES customer(customer_id),
    address_id      INTEGER         NOT NULL REFERENCES address(address_id),
    address_type    VARCHAR(20)     NOT NULL,
    is_default      BOOLEAN         DEFAULT FALSE,
    PRIMARY KEY (customer_id, address_id)
);

-- ═══════════════════════════════════════════
--  PRODUCT DOMAIN
-- ═══════════════════════════════════════════

CREATE TABLE category (
    category_id         SERIAL      PRIMARY KEY,
    name                VARCHAR(100) NOT NULL,
    slug                VARCHAR(120) NOT NULL UNIQUE,
    parent_category_id  INTEGER     REFERENCES category(category_id),
    description         TEXT
);

CREATE TABLE product (
    product_id      SERIAL          PRIMARY KEY,
    sku             VARCHAR(50)     NOT NULL UNIQUE,
    name            VARCHAR(255)    NOT NULL,
    description     TEXT,
    price           DECIMAL(10,2)   NOT NULL,
    weight_kg       DECIMAL(6,3),
    stock_quantity  INTEGER         NOT NULL DEFAULT 0,
    is_active       BOOLEAN         DEFAULT TRUE,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE product_category (
    product_id      INTEGER         NOT NULL REFERENCES product(product_id),
    category_id     INTEGER         NOT NULL REFERENCES category(category_id),
    PRIMARY KEY (product_id, category_id)
);

CREATE TABLE product_image (
    image_id        SERIAL          PRIMARY KEY,
    product_id      INTEGER         NOT NULL REFERENCES product(product_id),
    url             VARCHAR(500)    NOT NULL,
    alt_text        VARCHAR(255),
    sort_order      INTEGER         DEFAULT 0
);

CREATE TABLE product_review (
    review_id       SERIAL          PRIMARY KEY,
    product_id      INTEGER         NOT NULL REFERENCES product(product_id),
    customer_id     INTEGER         NOT NULL REFERENCES customer(customer_id),
    rating          SMALLINT        NOT NULL,
    title           VARCHAR(200),
    body            TEXT,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- ═══════════════════════════════════════════
--  ORDER / TRANSACTION DOMAIN
-- ═══════════════════════════════════════════

CREATE TABLE cart (
    cart_id         SERIAL          PRIMARY KEY,
    customer_id     INTEGER         NOT NULL REFERENCES customer(customer_id),
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE cart_item (
    cart_item_id    SERIAL          PRIMARY KEY,
    cart_id         INTEGER         NOT NULL REFERENCES cart(cart_id),
    product_id      INTEGER         NOT NULL REFERENCES product(product_id),
    quantity        INTEGER         NOT NULL DEFAULT 1
);

CREATE TABLE "order" (
    order_id            SERIAL      PRIMARY KEY,
    customer_id         INTEGER     NOT NULL REFERENCES customer(customer_id),
    shipping_address_id INTEGER     NOT NULL REFERENCES address(address_id),
    billing_address_id  INTEGER     NOT NULL REFERENCES address(address_id),
    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    subtotal            DECIMAL(10,2) NOT NULL,
    tax                 DECIMAL(10,2) NOT NULL DEFAULT 0,
    shipping_cost       DECIMAL(10,2) NOT NULL DEFAULT 0,
    total               DECIMAL(10,2) NOT NULL,
    created_at          TIMESTAMP   DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE order_item (
    order_item_id   SERIAL          PRIMARY KEY,
    order_id        INTEGER         NOT NULL REFERENCES "order"(order_id),
    product_id      INTEGER         NOT NULL REFERENCES product(product_id),
    quantity        INTEGER         NOT NULL,
    unit_price      DECIMAL(10,2)   NOT NULL
);

CREATE TABLE payment (
    payment_id      SERIAL          PRIMARY KEY,
    order_id        INTEGER         NOT NULL REFERENCES "order"(order_id),
    method          VARCHAR(30)     NOT NULL,
    amount          DECIMAL(10,2)   NOT NULL,
    currency        CHAR(3)         NOT NULL DEFAULT 'USD',
    status          VARCHAR(20)     NOT NULL DEFAULT 'pending',
    transaction_id  VARCHAR(100),
    paid_at         TIMESTAMP
);

CREATE TABLE shipment (
    shipment_id     SERIAL          PRIMARY KEY,
    order_id        INTEGER         NOT NULL REFERENCES "order"(order_id),
    carrier         VARCHAR(50)     NOT NULL,
    tracking_number VARCHAR(100),
    status          VARCHAR(20)     NOT NULL DEFAULT 'pending',
    shipped_at      TIMESTAMP,
    delivered_at    TIMESTAMP
);
SQLEOF

chown ga:ga /home/ga/Desktop/shopsphere_schema.sql 2>/dev/null || true
echo "Schema file created: /home/ga/Desktop/shopsphere_schema.sql"

# Record baseline state
INITIAL_COUNT=$(ls /home/ga/Desktop/*.drawio 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_drawio_count

date +%s > /tmp/task_start_timestamp

# Launch draw.io (startup dialog will appear)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_ecommerce_erd.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i}s"
        break
    fi
    sleep 1
done

sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Press Escape to dismiss startup dialog (blank canvas)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/ecommerce_erd_start.png 2>/dev/null || true

echo "=== Setup complete: shopsphere_schema.sql on Desktop, draw.io running with blank canvas ==="
