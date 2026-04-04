#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Adapt Stack Overflow Solution Task ==="

WORKSPACE_DIR="/home/ga/workspace/api_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{config,src/{middleware,utils},docs/references}

# Create CONVENTIONS.md
cat > "$WORKSPACE_DIR/CONVENTIONS.md" << 'EOF'
# Team Coding Conventions

## Naming Conventions
- Use `camelCase` for variables and functions (not `snake_case`)
- Prefix error handlers with `handle` (e.g., `handleRateLimitError`, `handleValidationError`)
- Use descriptive names (no single letters except loop counters)

## Import/Export Standards
- Always import configuration from `config/` directory
- Use relative imports for project files
- Group imports: external libs first, then internal modules

## Code Style
- Use async/await for asynchronous code (not callbacks or raw promises)
- Include JSDoc comments for exported functions
- **Always attribute external code sources** (Stack Overflow, blog posts, etc.) with: