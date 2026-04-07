# User Permissions Demo

This example demonstrates the comprehensive user permissions and access control system in gym-anything using the ubuntu-gnome-systemd preset.

## User Accounts Configured

### 0. GA User (Pre-existing)
- **Username**: `ga` (UID: 1000) - *This user already exists in the systemd preset*
- **Role**: Administrator with enhanced permissions
- **Permissions**:
  - Enhanced with sudo access and additional groups
  - VNC server runs under this user
  - Full system access for container management

### 1. Admin User
- **Username**: `admin` (UID: 1001)
- **Role**: Additional administrator with full system access
- **Permissions**:
  - Sudo access without password required
  - Member of system groups: sudo, docker, audio, video, input
  - Custom environment variables for admin tools
  - Secure home directory (700 permissions)

### 2. Developer User  
- **Username**: `developer` (UID: 1002)
- **Role**: Developer with container and development tool access
- **Permissions**:
  - Sudo access with password required
  - Docker access for container operations
  - Audio/video access for multimedia development
  - Process limit of 100 concurrent processes
  - Development environment variables

### 3. Guest User
- **Username**: `guest` (UID: 1003) 
- **Role**: Limited access guest user
- **Permissions**:
  - No sudo access
  - Basic audio/video access only
  - Resource limits: 50 processes, 512MB memory
  - Standard home directory permissions

### 4. Service Worker
- **Username**: `service_worker` (UID: 998)
- **Role**: System service account
- **Permissions**:
  - System user (UID < 1000)
  - No login shell access
  - No home directory
  - Minimal permissions for service operations

## SystemD Integration

This example uses the `ubuntu-gnome-systemd` preset which:

- Runs systemd as PID 1 for full system service support
- Pre-creates a `ga` user (UID 1000) that runs VNC and desktop services
- Provides a complete GNOME desktop environment
- Requires privileged container mode for full systemd functionality

## Usage

Run the environment:

```bash
python -m gym_anything.cli run examples/user_permissions_demo
```

The system will:
1. Start the systemd container
2. Wait for systemd to fully initialize
3. Configure the existing `ga` user with enhanced permissions
4. Create additional users (admin, developer, guest, service_worker)
5. Set up VNC access on the configured port

Connect via VNC to see the desktop environment with all configured users available.

## Testing User Access

You can test different user permissions by switching users in the terminal:

```bash
# The ga user already has VNC and desktop access
su - ga
sudo apt update  # Should work without password

# Switch to admin user (no password required for sudo)
su - admin
sudo apt update  # Should work without password

# Switch to developer user  
su - developer
sudo apt update  # Will prompt for password

# Switch to guest user
su - guest
sudo apt update  # Should fail - no sudo access
```

## SystemD Services

The environment includes systemd services like:
- TigerVNC server (running as ga user)
- GNOME desktop session
- PulseAudio for audio support
- Standard systemd services

## Configuration Features Demonstrated

- **Existing user enhancement**: Configuring permissions for preset users
- **Multiple user roles**: admin, developer, guest, service accounts
- **SystemD compatibility**: Works with systemd containers and services
- **VNC integration**: Leverages existing VNC setup while adding users
- **Resource management**: Process and memory limits per user
- **Security controls**: Fine-grained permissions and access controls

This demonstrates how gym-anything can extend existing preset configurations with sophisticated user management while maintaining compatibility with complex system setups like systemd containers.