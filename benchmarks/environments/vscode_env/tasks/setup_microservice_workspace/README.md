# Setup Microservice Workspace Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-root workspaces, workspace configuration, project organization  
**Duration**: 300 seconds  
**Steps**: ~80

## Objective

Create a multi-root workspace that combines three separate microservice repositories (auth-service, shared-models, api-gateway) into a single VSCode workspace for unified development.

## Expected Workflow

1. Use File menu → "Add Folder to Workspace..." to add first folder
2. Repeat to add remaining two folders
3. Use File menu → "Save Workspace As..." 
4. Save as `/home/ga/projects/microservices.code-workspace`
5. Verify all three folders appear in Explorer sidebar

## Alternative Approach

Create the workspace file manually:
1. Create file `/home/ga/projects/microservices.code-workspace`
2. Add JSON structure with folders array
3. Open workspace via File → "Open Workspace from File..."

## Verification

Checks for:
1. Workspace file exists at correct location
2. Valid JSON structure
3. Contains exactly 3 folders
4. Folders are: auth-service, shared-models, api-gateway
5. (Bonus) Workspace-level settings configured

**Pass Threshold**: 90% (4/5 criteria minimum)