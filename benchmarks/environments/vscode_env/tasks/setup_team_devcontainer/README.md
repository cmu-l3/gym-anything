# Setup Team Devcontainer Task

**Difficulty**: 🟡 Medium  
**Skills**: Development containers, team collaboration, JSON configuration, environment management  
**Duration**: 420 seconds  
**Steps**: ~35

## Objective

Configure a development container (devcontainer) for a Node.js project to ensure all team members work in identical, reproducible environments. This addresses the common "works on my machine" problem.

## Expected Workflow

1. Create `.devcontainer/` directory in project root
2. Create `devcontainer.json` configuration file
3. Configure Node.js 18 base image
4. Specify required extensions (ESLint, Prettier, GitLens)
5. Set post-create command to run `npm install`
6. Embed editor settings (format on save, Prettier as formatter)
7. Create team documentation explaining devcontainer usage

## Configuration Requirements

### devcontainer.json Structure