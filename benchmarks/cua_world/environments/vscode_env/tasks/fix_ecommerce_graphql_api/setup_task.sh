#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix E-commerce GraphQL API Task ==="

WORKSPACE_DIR="/home/ga/workspace/graphql_api"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"

cd "$WORKSPACE_DIR"

# 1. Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "ecommerce-graphql-api",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "start": "node src/server.js",
    "test": "node test.js"
  },
  "dependencies": {
    "@apollo/server": "^4.9.0",
    "dataloader": "^2.2.2",
    "graphql": "^16.8.0",
    "sqlite3": "^5.1.6"
  }
}
EOF

# 2. Generate Real-ish SQLite Data
echo "Generating SQLite database..."
python3 << 'PYDATA'
import sqlite3
import random

conn = sqlite3.connect('/home/ga/workspace/graphql_api/data/ecommerce.db')
c = conn.cursor()

c.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE products (id INTEGER PRIMARY KEY, category_id INTEGER, name TEXT, description TEXT, price INTEGER)')
c.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, firstName TEXT, lastName TEXT)')

categories = ['Electronics', 'Clothing', 'Home', 'Toys', 'Books', 'Groceries', 'Beauty']
for i, cat in enumerate(categories):
    c.execute('INSERT INTO categories VALUES (?, ?)', (i+1, cat))

# Insert ~50 products. Product 10 explicitly has NULL description to trigger bug.
for i in range(1, 51):
    cat_id = random.randint(1, len(categories))
    desc = f"Detailed description for high quality product {i}" if i != 10 else None
    price_cents = random.randint(500, 15000) # e.g. 500 = $5.00
    c.execute('INSERT INTO products (id, category_id, name, description, price) VALUES (?, ?, ?, ?, ?)',
              (i, cat_id, f"Product {i}", desc, price_cents))

c.execute('INSERT INTO users VALUES (1, "John", "Doe")')

conn.commit()
conn.close()
PYDATA

chown -R ga:ga "$WORKSPACE_DIR/data"

# 3. Create Source Code Files

# src/schema.graphql
cat > "$WORKSPACE_DIR/src/schema.graphql" << 'EOF'
type Query {
  products: [Product!]!
  categories: [Category!]!
  user(id: ID!): User
}

type Mutation {
  createOrder(userId: ID!, productId: ID!, quantity: Int!): Order!
}

type Product {
  id: ID!
  name: String!
  description: String!
  price: Float!
}

type Category {
  id: ID!
  name: String!
  products: [Product!]!
}

type User {
  id: ID!
  firstName: String!
  lastName: String!
  fullName: String!
}

type Order {
  id: ID!
  quantity: Int!
  total: Float!
}
EOF

# src/db.js
cat > "$WORKSPACE_DIR/src/db.js" << 'EOF'
import sqlite3 from 'sqlite3';

class Database {
  constructor() {
    this.db = new sqlite3.Database('./data/ecommerce.db');
    this.queryCount = 0;
  }

  async all(sql, params = []) {
    this.queryCount++;
    return new Promise((resolve, reject) => {
      this.db.all(sql, params, (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  async get(sql, params = []) {
    this.queryCount++;
    return new Promise((resolve, reject) => {
      this.db.get(sql, params, (err, row) => {
        if (err) reject(err);
        else resolve(row);
      });
    });
  }

  getAllProducts() { return this.all("SELECT * FROM products"); }
  getAllCategories() { return this.all("SELECT * FROM categories"); }
  getUser(id) { return this.get("SELECT * FROM users WHERE id = ?", [id]); }
  getProduct(id) { return this.get("SELECT * FROM products WHERE id = ?", [id]); }

  // Problematic N+1 method
  getProductsByCategory(categoryId) {
    return this.all("SELECT * FROM products WHERE category_id = ?", [categoryId]);
  }

  // Batched method meant for DataLoader
  getProductsByCategories(categoryIds) {
    const placeholders = categoryIds.map(() => '?').join(',');
    return this.all(`SELECT * FROM products WHERE category_id IN (${placeholders})`, categoryIds);
  }

  createOrder(userId, productId, quantity, total) {
    return { id: Math.floor(Math.random() * 1000), quantity, total };
  }
}

export const db = new Database();
EOF

# src/loaders.js
cat > "$WORKSPACE_DIR/src/loaders.js" << 'EOF'
import DataLoader from 'dataloader';

export const createLoaders = (db) => {
  return {
    productsByCategory: new DataLoader(async (categoryIds) => {
      const products = await db.getProductsByCategories(categoryIds);
      return categoryIds.map(id => products.filter(p => p.category_id === id));
    })
  };
};
EOF

# src/resolvers.js (Contains the 5 bugs)
cat > "$WORKSPACE_DIR/src/resolvers.js" << 'EOF'
import { GraphQLError } from 'graphql';

export const resolvers = {
  Query: {
    products: (_, __, { db }) => db.getAllProducts(),
    categories: (_, __, { db }) => db.getAllCategories(),
    user: (_, { id }, { db }) => db.getUser(id),
  },
  Mutation: {
    createOrder: async (_, { userId, productId, quantity }, { db }) => {
      // TODO: Needs validation so negative/zero quantities are rejected
      const product = await db.getProduct(productId);
      if (!product) throw new GraphQLError("Product not found");
      const total = (product.price / 100) * quantity;
      return db.createOrder(userId, productId, quantity, total);
    }
  },
  Product: {
    // BUG 1: Price is returned in cents (int) but schema expects Float (dollars)
    price: (product) => product.price,
    // BUG 2: Crashes if description is null in the database
    description: (product) => product.description,
  },
  Category: {
    // BUG 4: N+1 issue. Uses db directly instead of the DataLoader
    products: (category, _, { db, loaders }) => db.getProductsByCategory(category.id),
  },
  User: {
    // BUG 3: Missing fullName resolver
  }
};
EOF

# src/server.js
cat > "$WORKSPACE_DIR/src/server.js" << 'EOF'
import { ApolloServer } from '@apollo/server';
import { startStandaloneServer } from '@apollo/server/standalone';
import fs from 'fs';
import { resolvers } from './resolvers.js';
import { db } from './db.js';
import { createLoaders } from './loaders.js';

const typeDefs = fs.readFileSync('./src/schema.graphql', 'utf8');

export const server = new ApolloServer({ typeDefs, resolvers });

if (process.env.NODE_ENV !== 'test') {
  const { url } = await startStandaloneServer(server, {
    listen: { port: 4000 },
    context: async () => ({
      db,
      loaders: createLoaders(db)
    }),
  });
  console.log(`🚀 Server ready at ${url}`);
}
EOF

# test.js (For the agent to run)
cat > "$WORKSPACE_DIR/test.js" << 'EOF'
import { server } from './src/server.js';
import { db } from './src/db.js';
import { createLoaders } from './src/loaders.js';

async function runTests() {
  console.log("=== Running API Tests ===");
  const contextValue = { db, loaders: createLoaders(db) };

  // 1. Price check
  const res1 = await server.executeOperation({ query: '{ products { price } }' }, { contextValue });
  console.log("1. Price Check (Expect float like 15.99):", res1.body.singleResult.data?.products[0]?.price);

  // 2. Null description
  const res2 = await server.executeOperation({ query: '{ products { description } }' }, { contextValue });
  console.log("2. Null Description Check (Expect no errors):", res2.body.singleResult.errors ? "FAILED - " + res2.body.singleResult.errors[0].message : "PASSED");

  // 3. User Full Name
  const res3 = await server.executeOperation({ query: '{ user(id:1) { fullName } }' }, { contextValue });
  console.log("3. FullName Check (Expect John Doe):", res3.body.singleResult.errors ? "FAILED" : res3.body.singleResult.data?.user?.fullName);

  // 4. Input validation
  const res4 = await server.executeOperation({ query: 'mutation { createOrder(userId:1, productId:1, quantity:-5) { id } }' }, { contextValue });
  console.log("4. Validation Check (Expect 'Quantity must be greater than zero'):",
      res4.body.singleResult.errors ? res4.body.singleResult.errors[0].message : "FAILED - No error thrown");

  // 5. N+1 Query check
  db.queryCount = 0;
  await server.executeOperation({ query: '{ categories { products { id } } }' }, { contextValue });
  console.log("5. N+1 Queries Executed:", db.queryCount, "(Should be exactly 2 if DataLoader is used)");

  process.exit(0);
}
runTests().catch(console.error);
EOF

chown -R ga:ga "$WORKSPACE_DIR"

# 4. Hidden Verification Script (Saved in /tmp so agent doesn't easily modify it)
cat > "/tmp/hidden_verify.js" << 'EOF'
import { server } from '/home/ga/workspace/graphql_api/src/server.js';
import { db } from '/home/ga/workspace/graphql_api/src/db.js';
import { createLoaders } from '/home/ga/workspace/graphql_api/src/loaders.js';
import fs from 'fs';

async function verify() {
  const contextValue = { db, loaders: createLoaders(db) };
  const results = {
    price_float: false,
    null_description: false,
    full_name: false,
    input_validation: false,
    n_plus_one_fixed: false,
    query_count: 0
  };

  try {
    const res1 = await server.executeOperation({ query: '{ products { price } }' }, { contextValue });
    const firstPrice = res1.body.singleResult.data?.products[0]?.price;
    // Database has prices in cents (e.g., > 500). If float is returned, it will be < 200 likely, or just check it has decimals
    if (firstPrice && firstPrice < 500 && firstPrice % 1 !== 0) results.price_float = true;

    const res2 = await server.executeOperation({ query: '{ products { description } }' }, { contextValue });
    const hasNullFallback = res2.body.singleResult.data?.products.some(p => p.description === "No description available");
    if (!res2.body.singleResult.errors && hasNullFallback) results.null_description = true;

    const res3 = await server.executeOperation({ query: '{ user(id:1) { fullName } }' }, { contextValue });
    if (res3.body.singleResult.data?.user?.fullName === "John Doe") results.full_name = true;

    const res4 = await server.executeOperation({ query: 'mutation { createOrder(userId:1, productId:1, quantity:-5) { id } }' }, { contextValue });
    if (res4.body.singleResult.errors && res4.body.singleResult.errors[0].message === "Quantity must be greater than zero") results.input_validation = true;

    db.queryCount = 0;
    await server.executeOperation({ query: '{ categories { products { id } } }' }, { contextValue });
    results.query_count = db.queryCount;
    if (db.queryCount > 0 && db.queryCount <= 2) results.n_plus_one_fixed = true;

  } catch (e) {
    results.error = e.message;
  }

  fs.writeFileSync('/tmp/graphql_api_test_results.json', JSON.stringify(results, null, 2));
  process.exit(0);
}
verify().catch(console.error);
EOF

# 5. Install Node Modules
echo "Installing Node.js dependencies..."
sudo -u ga bash -c "cd $WORKSPACE_DIR && npm install --no-audit --no-fund --legacy-peer-deps > /tmp/npm_install.log 2>&1"

# 6. Record Initial Timestamps (Anti-gaming)
stat -c %Y "$WORKSPACE_DIR/src/resolvers.js" > /tmp/task_start_time.txt
date +%s > /tmp/task_start_timestamp.txt

# 7. Launch VS Code
echo "Launching VS Code..."
sudo -u ga DISPLAY=:1 code "$WORKSPACE_DIR" > /tmp/vscode_launch.log 2>&1 &
sleep 5

# Focus and Maximize
focus_vscode_window 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial Screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="