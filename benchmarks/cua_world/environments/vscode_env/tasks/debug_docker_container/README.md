# Debug Docker Container Task

**Difficulty**: 🟡 Medium  
**Skills**: Docker integration, remote debugging, VSCode configuration, debugpy  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Configure VSCode to attach a debugger to a Python Flask application running inside a Docker container. This involves installing debugpy in the container, exposing the debug port, modifying the application code, and creating a proper launch configuration.

## Background

A Flask API is running in a Docker container but has a bug that only appears in the containerized environment. You need to set up remote debugging so you can set breakpoints and inspect variables inside the running container.

## Expected Workflow

1. **Install debugpy in container**: