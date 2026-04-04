# Organize Development Terminals Task

**Difficulty**: 🟡 Medium  
**Skills**: Terminal management, workspace organization, developer workflow  
**Duration**: 300 seconds  
**Steps**: ~60

## Objective

Set up an organized multi-terminal workspace for full-stack development. Create 4 named terminals arranged in a split layout, each in the correct working directory.

## Expected Workflow

1. Open integrated terminal (Ctrl+` or View → Terminal)
2. Create first terminal and rename to "frontend-dev"
   - Right-click terminal tab → Rename
   - Navigate: `cd frontend`
3. Split terminal (click split icon or Ctrl+Shift+5)
4. Rename second to "backend-api"
   - Navigate: `cd backend`
5. Split again to create third terminal
6. Rename to "worker"
   - Navigate: `cd backend`
7. Split again to create fourth terminal
8. Rename to "logs"
   - Navigate: `cd logs`

## Required Terminal Configuration

| Terminal Name | Working Directory | Purpose |
|--------------|-------------------|---------|
| frontend-dev | `/home/ga/workspace/dev_project/frontend` | React dev server |
| backend-api | `/home/ga/workspace/dev_project/backend` | Flask API server |
| worker | `/home/ga/workspace/dev_project/backend` | Background worker |
| logs | `/home/ga/workspace/dev_project/logs` | Log monitoring |

## Verification

Checks for:
1. Exactly 4 terminals exist
2. All terminals have custom names (not default "bash")
3. Names match: "frontend-dev", "backend-api", "worker", "logs"
4. Terminals are in split layout (not all tabs)
5. Each terminal is in correct working directory

**Pass Threshold**: 80% (4/5 criteria)