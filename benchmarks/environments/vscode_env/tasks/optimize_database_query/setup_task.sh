#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Optimize Database Query Task ==="

WORKSPACE_DIR="/home/ga/workspace/analytics_db"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create schema reference file
cat > "$WORKSPACE_DIR/schema.txt" << 'EOF'
Database Schema - E-commerce Analytics

Tables:
--------

users
  - id (INTEGER, PRIMARY KEY)
  - username (VARCHAR(50))
  - email (VARCHAR(100))
  - created_at (TIMESTAMP)

orders
  - id (INTEGER, PRIMARY KEY)
  - user_id (INTEGER, FOREIGN KEY → users.id)
  - total_amount (DECIMAL(10,2))
  - order_date (TIMESTAMP)
  - status (VARCHAR(20))

order_items
  - id (INTEGER, PRIMARY KEY)
  - order_id (INTEGER, FOREIGN KEY → orders.id)
  - product_id (INTEGER, FOREIGN KEY → products.id)
  - quantity (INTEGER)
  - price (DECIMAL(10,2))

products
  - id (INTEGER, PRIMARY KEY)
  - name (VARCHAR(200))
  - sku (VARCHAR(50))
  - category_id (INTEGER, FOREIGN KEY → categories.id)
  - price (DECIMAL(10,2))

categories
  - id (INTEGER, PRIMARY KEY)
  - name (VARCHAR(100))
  - parent_category_id (INTEGER, FOREIGN KEY → categories.id, nullable)

Indexes:
- orders.user_id
- order_items.order_id
- order_items.product_id
- products.category_id
EOF

# Create README with task context
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Analytics Database Queries

## Current Problem

The "Top Products by Category" report is timing out after 30 seconds due to N+1 query pattern. The current implementation:

1. Fetches all categories (1 query)
2. For each category, fetches products (N queries)
3. For each product, fetches sales data (N*M queries)

This results in hundreds of queries for a single report.

## Task

Create `top_products_by_category.sql` that efficiently retrieves product sales data in a single optimized query.

### Required Output Columns:
- `category_name` - Name of the product category
- `product_name` - Name of the product
- `total_quantity` - Total quantity sold (SUM of order_items.quantity)
- `total_revenue` - Total revenue (SUM of order_items.quantity * order_items.price)

### Requirements:
- Use JOIN to combine orders, order_items, products, and categories
- Aggregate sales data using SUM
- Group by category and product
- Order by total revenue (highest first)
- Limit to top 100 results
- Format with SQL best practices (uppercase keywords, proper indentation)
- Add comments explaining the query

### Expected Performance:
Single query execution instead of N+1 pattern should reduce execution time from 30+ seconds to under 1 second.
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/README.md'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Optimize Database Query Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review the schema.txt and README.md files in the workspace"
echo "  2. Create a new file: top_products_by_category.sql"
echo "  3. Write a SQL query with JOINs across multiple tables"
echo "  4. Use aggregate functions (SUM) and GROUP BY"
echo "  5. Format with uppercase keywords and proper indentation"
echo "  6. Add at least one comment explaining the query"
echo "  7. Save the file (Ctrl+S)"
echo ""
echo "Workspace: $WORKSPACE_DIR"