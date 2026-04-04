#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Accessibility Violations Task ==="

WORKSPACE_DIR="/home/ga/workspace/accessibility-fixes"
COMPONENT_DIR="$WORKSPACE_DIR/src/components"

# Create directory structure
sudo -u ga mkdir -p "$COMPONENT_DIR"

# Create audit report
cat > "$WORKSPACE_DIR/audit_report.md" << 'EOF'
# Accessibility Audit Report - DataTable Component

**Date**: 2024-01-15  
**Auditor**: QA Team  
**Tool**: axe DevTools + Manual Testing  
**Severity**: CRITICAL - Blocks contract renewal

---

## Critical Violations Found

### 1. Missing table headers
- **Issue**: `<table>` element has no `<thead>` or `<th>` elements
- **Current state**: Headers are in `<td>` with bold styling
- **Impact**: Screen reader users cannot understand table structure
- **WCAG**: 1.3.1 Info and Relationships (Level A)
- **Fix**: Add proper `<thead>` with `<th scope="col">` for each column

### 2. Non-semantic button
- **Issue**: Clickable `<div>` with onClick instead of `<button>`
- **Current state**: `<div className="sort-button" onClick={handleSort}>`
- **Impact**: Keyboard users cannot access "Sort" functionality, not in tab order
- **WCAG**: 4.1.2 Name, Role, Value (Level A)
- **Fix**: Replace with `<button>` element, keep onClick handler

### 3. Missing ARIA label
- **Issue**: Sort button has no accessible name
- **Current state**: Button only shows "Sort" visually
- **Impact**: Screen reader announces "button" with no context about what it sorts
- **WCAG**: 4.1.2 Name, Role, Value (Level A)
- **Fix**: Add `aria-label` describing the sort action (e.g., "Sort table by name")

### 4. Missing table caption
- **Issue**: No `<caption>` or `aria-label` on table
- **Current state**: Table has no programmatically associated description
- **Impact**: Users don't know what data the table represents
- **WCAG**: 2.4.6 Headings and Labels (Level AA)
- **Fix**: Add `<caption>` as first child of `<table>`, or add `aria-label` to table

---

## Required Fixes Checklist
- [ ] Add proper `<thead>` and `<th scope="col">` elements for Name, Email, Role
- [ ] Replace sort `<div>` with semantic `<button>` element
- [ ] Add descriptive `aria-label` to sort button
- [ ] Add `<caption>` to table or `aria-label` on `<table>` tag

**Deadline**: Before contract renewal next week  
**Priority**: P0 - Must fix immediately
EOF

# Create violating component with clear structure
cat > "$COMPONENT_DIR/DataTable.jsx" << 'EOF'
import React, { useState } from 'react';

function DataTable({ data }) {
  const [sortOrder, setSortOrder] = useState('asc');

  const handleSort = () => {
    setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
  };

  const sortedData = [...data].sort((a, b) => {
    return sortOrder === 'asc' 
      ? a.name.localeCompare(b.name)
      : b.name.localeCompare(a.name);
  });

  return (
    <div className="data-table-container">
      <div className="sort-button" onClick={handleSort}>
        Sort
      </div>
      
      <table>
        <tbody>
          <tr>
            <td><strong>Name</strong></td>
            <td><strong>Email</strong></td>
            <td><strong>Role</strong></td>
          </tr>
          {sortedData.map((user, idx) => (
            <tr key={idx}>
              <td>{user.name}</td>
              <td>{user.email}</td>
              <td>{user.role}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default DataTable;
EOF

# Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "accessibility-fixes",
  "version": "1.0.0",
  "description": "Fixing accessibility violations in React components",
  "main": "src/index.js",
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "eslint-plugin-jsx-a11y": "^6.7.1"
  }
}
EOF

# Create README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Accessibility Fixes Project

This project contains React components that need accessibility remediation for WCAG 2.1 Level AA compliance.

## Current Task
Fix WCAG violations in `src/components/DataTable.jsx` according to `audit_report.md`.

## Files
- `audit_report.md` - Detailed accessibility audit findings
- `src/components/DataTable.jsx` - Component with violations (needs fixes)

## Instructions
1. Read the audit report to understand all violations
2. Open DataTable.jsx
3. Apply all 4 required fixes
4. Save the file

## Testing
After fixes, the component should:
- Use semantic HTML elements
- Be keyboard accessible
- Work with screen readers
- Meet WCAG 2.1 Level AA standards
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the audit report first so agent sees it
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/audit_report.md'" || true

sleep 1

echo "=== Fix Accessibility Violations Task Setup Complete ==="
echo "📋 Workspace: $WORKSPACE_DIR"
echo "📝 Instructions:"
echo "  1. Read audit_report.md (should be open)"
echo "  2. Open src/components/DataTable.jsx"
echo "  3. Fix all 4 WCAG violations:"
echo "     - Replace <div> with <button>"
echo "     - Add aria-label to button"
echo "     - Add <thead> with <th scope=\"col\">"
echo "     - Add <caption> to table"
echo "  4. Save the file (Ctrl+S)"