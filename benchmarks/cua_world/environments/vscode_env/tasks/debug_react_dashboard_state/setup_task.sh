#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Debug React Dashboard State Task ==="

WORKSPACE_DIR="/home/ga/workspace/ecommerce_dashboard"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/components"

# ──────────────────────────────────────────────────────────────
# 1. LiveTicker.jsx (BUG: Stale Closure in setInterval)
# ──────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/components/LiveTicker.jsx" << 'EOF'
import React, { useState, useEffect } from 'react';

export default function LiveTicker() {
    const [revenue, setRevenue] = useState(10000);

    useEffect(() => {
        // BUG: Stale closure on 'revenue' because of empty dependency array
        const timer = setInterval(() => {
            setRevenue(revenue + 15);
        }, 1000);

        return () => clearInterval(timer);
    }, []);

    return (
        <div className="ticker-box">
            <h3>Live Revenue</h3>
            <p>${revenue}</p>
        </div>
    );
}
EOF

# ──────────────────────────────────────────────────────────────
# 2. OrderSearch.jsx (BUG: Fetch Race Condition)
# ──────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/components/OrderSearch.jsx" << 'EOF'
import React, { useState, useEffect } from 'react';

export default function OrderSearch({ query }) {
    const [results, setResults] = useState([]);

    useEffect(() => {
        if (!query) return;

        // BUG: Race condition on network fetch (no AbortController or ignore flag)
        fetch(`/api/orders?q=${query}`)
            .then(res => res.json())
            .then(data => {
                setResults(data);
            });
            
    }, [query]);

    return (
        <div className="search-results">
            {results.map(r => <div key={r.id}>{r.customer}</div>)}
        </div>
    );
}
EOF

# ──────────────────────────────────────────────────────────────
# 3. MetricsChart.jsx (BUG: Infinite Loop via Reference Equality)
# ──────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/components/MetricsChart.jsx" << 'EOF'
import React, { useState, useEffect } from 'react';

export default function MetricsChart({ data }) {
    const [processed, setProcessed] = useState([]);
    
    // BUG: Object recreated every render, causing infinite effect loops
    const config = { theme: 'dark', animated: true };

    useEffect(() => {
        if (!data) return;
        setProcessed(data.map(d => ({ ...d, ...config })));
    }, [data, config]);

    return (
        <div className="metrics-chart">
            <p>Data points loaded: {processed.length}</p>
        </div>
    );
}
EOF

# ──────────────────────────────────────────────────────────────
# 4. ResponsiveContainer.jsx (BUG: Memory Leak via Event Listener)
# ──────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/components/ResponsiveContainer.jsx" << 'EOF'
import React, { useState, useEffect } from 'react';

export default function ResponsiveContainer({ children }) {
    const [width, setWidth] = useState(window.innerWidth);

    useEffect(() => {
        const handleResize = () => setWidth(window.innerWidth);
        
        // BUG: Missing cleanup function, causes memory leak
        window.addEventListener('resize', handleResize);
    }, []);

    return (
        <div style={{ width: `${width}px`, overflow: 'hidden' }}>
            {children}
        </div>
    );
}
EOF

# ──────────────────────────────────────────────────────────────
# 5. OrderList.jsx (BUG: State Mutation)
# ──────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/components/OrderList.jsx" << 'EOF'
import React, { useState } from 'react';

export default function OrderList({ initialOrders }) {
    const [orders, setOrders] = useState(initialOrders || []);

    const markShipped = (index) => {
        // BUG: Mutating state array directly prevents React from re-rendering
        orders[index].status = 'Shipped';
        setOrders(orders);
    };

    return (
        <ul className="order-list">
            {orders.map((o, i) => (
                <li key={o.id}>
                    Order #{o.id} - {o.status} 
                    <button onClick={() => markShipped(i)}>Mark Shipped</button>
                </li>
            ))}
        </ul>
    );
}
EOF

# Provide standard files to complete the mock project
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "ecommerce-dashboard",
  "version": "1.0.0",
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  }
}
EOF

# Set permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Record task start time and launch VS Code
date +%s > /tmp/task_start_time.txt
echo "Launching VS Code..."

sudo -u ga DISPLAY=:1 code "$WORKSPACE_DIR" --new-window &
sleep 5

# Focus and maximize
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="