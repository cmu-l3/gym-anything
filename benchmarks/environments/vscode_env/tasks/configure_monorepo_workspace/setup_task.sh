#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Monorepo Workspace Task ==="

WORKSPACE_DIR="/home/ga/workspace/monorepo-project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create root package.json for Yarn workspaces
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "monorepo-project",
  "version": "1.0.0",
  "private": true,
  "workspaces": [
    "packages/*"
  ],
  "devDependencies": {
    "typescript": "^5.0.0"
  }
}
EOF

# Create packages directory
sudo -u ga mkdir -p "$WORKSPACE_DIR/packages"

# Package 1: shared-utils
SHARED_UTILS="$WORKSPACE_DIR/packages/shared-utils"
sudo -u ga mkdir -p "$SHARED_UTILS/src"

cat > "$SHARED_UTILS/package.json" << 'EOF'
{
  "name": "@monorepo/shared-utils",
  "version": "1.0.0",
  "main": "./src/index.ts",
  "types": "./src/index.ts"
}
EOF

cat > "$SHARED_UTILS/tsconfig.json" << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "declaration": true,
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"]
}
EOF

cat > "$SHARED_UTILS/src/index.ts" << 'EOF'
export function formatDate(date: Date): string {
  return date.toISOString().split('T')[0];
}

export function capitalize(str: string): string {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

export const APP_VERSION = "1.0.0";
EOF

# Package 2: ui-components
UI_COMPONENTS="$WORKSPACE_DIR/packages/ui-components"
sudo -u ga mkdir -p "$UI_COMPONENTS/src"

cat > "$UI_COMPONENTS/package.json" << 'EOF'
{
  "name": "@monorepo/ui-components",
  "version": "1.0.0",
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "dependencies": {
    "@monorepo/shared-utils": "1.0.0"
  }
}
EOF

cat > "$UI_COMPONENTS/tsconfig.json" << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020", "DOM"],
    "declaration": true,
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"]
}
EOF

cat > "$UI_COMPONENTS/src/index.ts" << 'EOF'
import { capitalize } from '@monorepo/shared-utils';

export class Button {
  constructor(private label: string) {}

  render(): string {
    return `<button>${capitalize(this.label)}</button>`;
  }
}

export class Card {
  constructor(private title: string, private content: string) {}

  render(): string {
    return `<div class="card"><h3>${this.title}</h3><p>${this.content}</p></div>`;
  }
}
EOF

# Package 3: api-client
API_CLIENT="$WORKSPACE_DIR/packages/api-client"
sudo -u ga mkdir -p "$API_CLIENT/src"

cat > "$API_CLIENT/package.json" << 'EOF'
{
  "name": "@monorepo/api-client",
  "version": "1.0.0",
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "dependencies": {
    "@monorepo/shared-utils": "1.0.0"
  }
}
EOF

cat > "$API_CLIENT/tsconfig.json" << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "declaration": true,
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"]
}
EOF

cat > "$API_CLIENT/src/index.ts" << 'EOF'
import { formatDate } from '@monorepo/shared-utils';

export interface ApiResponse<T> {
  data: T;
  timestamp: string;
}

export class ApiClient {
  constructor(private baseUrl: string) {}

  async fetch<T>(endpoint: string): Promise<ApiResponse<T>> {
    const response = await fetch(`${this.baseUrl}${endpoint}`);
    const data = await response.json();
    return {
      data,
      timestamp: formatDate(new Date())
    };
  }
}
EOF

# Package 4: backend
BACKEND="$WORKSPACE_DIR/packages/backend"
sudo -u ga mkdir -p "$BACKEND/src"

cat > "$BACKEND/package.json" << 'EOF'
{
  "name": "@monorepo/backend",
  "version": "1.0.0",
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "dependencies": {
    "@monorepo/shared-utils": "1.0.0",
    "@monorepo/api-client": "1.0.0"
  }
}
EOF

cat > "$BACKEND/tsconfig.json" << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "declaration": true,
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"]
}
EOF

cat > "$BACKEND/src/index.ts" << 'EOF'
import { APP_VERSION } from '@monorepo/shared-utils';
import { ApiClient } from '@monorepo/api-client';

export class Server {
  private apiClient: ApiClient;

  constructor() {
    this.apiClient = new ApiClient('http://localhost:3000');
  }

  getVersion(): string {
    return APP_VERSION;
  }

  async handleRequest(path: string): Promise<any> {
    return await this.apiClient.fetch(path);
  }
}
EOF

# Create a basic root tsconfig (not properly configured for workspace yet)
cat > "$WORKSPACE_DIR/tsconfig.json" << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  }
}
EOF

# Create .vscode directory (empty - agent needs to configure it)
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Create a README for the user
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Monorepo Project

This is a TypeScript monorepo with 4 packages:

- `@monorepo/shared-utils` - Common utilities
- `@monorepo/ui-components` - UI components (depends on shared-utils)
- `@monorepo/api-client` - API client (depends on shared-utils)
- `@monorepo/backend` - Backend server (depends on shared-utils and api-client)

## Problem

Currently, VSCode shows TypeScript errors for cross-package imports because the workspace is not properly configured.

## Solution Needed

Configure VSCode workspace settings to:
1. Enable TypeScript multi-project mode
2. Set up project references
3. Optimize search and file watching
4. Enable composite mode for packages

See the task instructions for details.
EOF

sudo chown ga:ga "$WORKSPACE_DIR/README.md"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/README.md'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Configure Monorepo Workspace Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Create .vscode/settings.json with TypeScript multi-project settings"
echo "  2. Configure search.exclude and files.watcherExclude for node_modules"
echo "  3. Modify root tsconfig.json to add 'references' array"
echo "  4. Update package tsconfig.json files to enable 'composite: true'"
echo ""
echo "Directory: $WORKSPACE_DIR"
echo "Packages: ui-components, api-client, backend, shared-utils"