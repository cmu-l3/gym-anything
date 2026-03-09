# Remote SSH Development Setup Task

**Difficulty**: 🟡 Medium  
**Skills**: Remote Development, SSH configuration, Extension management, Remote execution  
**Duration**: 420 seconds  
**Steps**: ~40

## Objective

Configure VSCode to connect to a remote development server via SSH, install extensions remotely, and verify remote code execution by creating and running a Node.js HTTP server.

## Real-World Context

Many developers work with remote development servers for:
- Resource-intensive applications (microservices, databases)
- Cloud development environments (AWS EC2, GCP, Azure)
- Team-standardized development servers
- GPU/specialized hardware access
- Embedded systems and IoT development

This task simulates connecting to a remote Linux server with more computational resources than your local machine.

## Expected Workflow

1. **Configure SSH**: Create SSH config file with remote server details
2. **Connect via VSCode**: Use Remote-SSH extension to connect
3. **Accept host key**: Confirm SSH fingerprint on first connection
4. **Wait for installation**: VSCode Server installs on remote automatically
5. **Install extensions remotely**: Install ESLint extension on the remote environment
6. **Create workspace**: Set up project directory on remote
7. **Write and run code**: Create Node.js server and execute on remote machine
8. **Verify remote execution**: Confirm process runs on remote, not locally

## Verification

Checks for:
1. SSH config file with correct connection details
2. Remote VSCode Server installed
3. ESLint extension installed remotely (not just locally)
4. Remote workspace folder exists
5. Node.js application file created with correct content
6. Process running on remote machine as `developer` user
7. Terminal shows remote prompt

**Pass Threshold**: 85% (6-7/8 criteria)

## Key Learning Points

- Understanding VSCode Remote Development architecture
- SSH configuration and key-based authentication
- Distinguishing local vs. remote execution contexts
- Managing extensions in remote environments
- Remote terminal usage and process verification