#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Screen Share Preparation Task ==="

WORKSPACE_DIR="/home/ga/workspace/screen_share_task"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create work files (should be kept)
cat > "$WORKSPACE_DIR/presentation_demo.py" << 'EOF'
"""
Demo script for client presentation
"""

def calculate_metrics(data):
    """Calculate key business metrics"""
    total = sum(data)
    average = total / len(data) if data else 0
    return {
        'total': total,
        'average': average,
        'count': len(data)
    }

def generate_report(metrics):
    """Generate presentation-ready report"""
    return f"""
    Business Metrics Report
    =======================
    Total: ${metrics['total']:,.2f}
    Average: ${metrics['average']:,.2f}
    Data Points: {metrics['count']}
    """

if __name__ == '__main__':
    sample_data = [1200, 1500, 1800, 2100, 1900]
    metrics = calculate_metrics(sample_data)
    print(generate_report(metrics))
EOF

cat > "$WORKSPACE_DIR/client_api.js" << 'EOF'
// Client API Integration
// Demo for stakeholder presentation

const API_ENDPOINT = 'https://api.example.com/v1';

async function fetchClientData(clientId) {
    const response = await fetch(`${API_ENDPOINT}/clients/${clientId}`);
    return await response.json();
}

async function updateClientStatus(clientId, status) {
    const response = await fetch(`${API_ENDPOINT}/clients/${clientId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status })
    });
    return await response.json();
}

module.exports = { fetchClientData, updateClientStatus };
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Client Demo Project

## Overview
This project demonstrates our API integration capabilities for the client presentation.

## Features
- Real-time data fetching
- Metrics calculation
- Report generation

## Usage