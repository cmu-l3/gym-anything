#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Generate Mock Data Task ==="

WORKSPACE_DIR="/home/ga/workspace/ecommerce-mocks"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create README with task requirements
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Mock Data Generator Task

## Goal
Create a TypeScript/JavaScript file that generates realistic mock data for an e-commerce application.

## Requirements
1. Generate at least 3 entity types: Users, Products, and Orders
2. Maintain referential integrity (orders reference valid users and products)
3. Calculate order totals correctly (items + shipping + tax - discounts)
4. Include edge cases: international addresses, bulk orders, promo codes
5. Use deterministic random generation (seeding) for reproducible tests

## Example Structure