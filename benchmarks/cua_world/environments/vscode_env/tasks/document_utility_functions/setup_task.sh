#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Document Utility Functions Task ==="

WORKSPACE_DIR="/home/ga/workspace"
UTILS_DIR="$WORKSPACE_DIR/utils"

sudo -u ga mkdir -p "$UTILS_DIR"

# Create the undocumented TypeScript helpers file
cat > "$UTILS_DIR/helpers.ts" << 'EOF'
export function formatCurrency(amount: number, locale?: string): string {
  const loc = locale || 'en-US';
  return new Intl.NumberFormat(loc, { 
    style: 'currency', 
    currency: 'USD' 
  }).format(amount);
}

export function debounce<T extends (...args: any[]) => any>(
  func: T, 
  wait: number
): T {
  let timeout: NodeJS.Timeout | null = null;
  return ((...args: Parameters<T>) => {
    if (timeout) clearTimeout(timeout);
    timeout = setTimeout(() => func(...args), wait);
  }) as T;
}

export function deepMerge(target: any, source: any): any {
  const output = { ...target };
  if (isObject(target) && isObject(source)) {
    Object.keys(source).forEach(key => {
      if (isObject(source[key])) {
        if (!(key in target)) {
          output[key] = source[key];
        } else {
          output[key] = deepMerge(target[key], source[key]);
        }
      } else {
        output[key] = source[key];
      }
    });
  }
  return output;
}

function isObject(item: any): boolean {
  return item && typeof item === 'object' && !Array.isArray(item);
}
EOF

# Create a test usage file to demonstrate IntelliSense
cat > "$WORKSPACE_DIR/test_usage.ts" << 'EOF'
import { formatCurrency, debounce, deepMerge } from './utils/helpers';

// Test formatCurrency
const price = formatCurrency(1234.56);
const priceEuro = formatCurrency(1234.56, 'de-DE');

// Test debounce
const searchHandler = debounce((query: string) => {
  console.log('Searching for:', query);
}, 300);

// Test deepMerge
const config = deepMerge(
  { api: { timeout: 5000 } },
  { api: { retries: 3 }, debug: true }
);

console.log(price, config);
EOF

# Create tsconfig.json for TypeScript support
cat > "$WORKSPACE_DIR/tsconfig.json" << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["**/*.ts"],
  "exclude": ["node_modules", "dist"]
}
EOF

# Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "utils-documentation",
  "version": "1.0.0",
  "description": "Utility functions documentation task",
  "main": "index.js",
  "scripts": {
    "build": "tsc"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "typescript": "^5.0.0"
  }
}
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the helpers.ts file
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$UTILS_DIR/helpers.ts'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Document Utility Functions Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Read and understand each function in helpers.ts"
echo "  2. Add JSDoc comments above each function"
echo "  3. Include @param, @returns, and @example tags"
echo "  4. Ensure descriptions are clear and accurate"
echo "  5. Save the file (Ctrl+S)"