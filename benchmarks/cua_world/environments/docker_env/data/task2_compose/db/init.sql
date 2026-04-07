-- AcmeCorp E-Commerce Database Schema
-- Initial schema for the store database

CREATE TABLE IF NOT EXISTS products (
    id          SERIAL PRIMARY KEY,
    sku         VARCHAR(50) UNIQUE NOT NULL,
    name        VARCHAR(255) NOT NULL,
    description TEXT,
    price       NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    stock_qty   INTEGER NOT NULL DEFAULT 0,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS orders (
    id          SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    status      VARCHAR(50) NOT NULL DEFAULT 'pending',
    total       NUMERIC(10, 2) NOT NULL,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS order_items (
    id          SERIAL PRIMARY KEY,
    order_id    INTEGER NOT NULL REFERENCES orders(id),
    product_id  INTEGER NOT NULL REFERENCES products(id),
    quantity    INTEGER NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(10, 2) NOT NULL
);

-- Seed data
INSERT INTO products (sku, name, description, price, stock_qty) VALUES
    ('LAPTOP-001', 'ProBook 15 Laptop', '15-inch business laptop', 1299.99, 42),
    ('MOUSE-002', 'Wireless Ergonomic Mouse', 'Ergonomic wireless mouse', 49.99, 185),
    ('KB-003', 'Mechanical Keyboard', 'Tenkeyless mechanical keyboard', 129.99, 67),
    ('MONITOR-004', '27-inch 4K Display', '4K IPS monitor, 60Hz', 549.99, 28),
    ('HEADSET-005', 'Noise-Cancelling Headset', 'Over-ear ANC headset', 199.99, 93)
ON CONFLICT DO NOTHING;
