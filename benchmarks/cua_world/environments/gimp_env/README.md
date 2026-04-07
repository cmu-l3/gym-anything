# GIMP Environment Example

This example demonstrates how to create software-specific environments using gym-anything's hooks system. It extends the `ubuntu-gnome-systemd` base preset with GIMP and related graphics tools.

## What This Example Shows

### 🔧 **Easy Software Installation**
- Uses existing `hooks` system instead of writing custom Dockerfiles
- `pre_start` hook installs GIMP and graphics packages
- `post_start` hook configures GIMP for users

### 📁 **File Organization**
```
gimp_env/
├── env.json              # Environment configuration
├── scripts/              # Setup scripts (mounted as /workspace/setup)
│   ├── install_gimp.sh   # Software installation (pre_start hook)
│   └── setup_gimp.sh     # User configuration (post_start hook)
├── config/               # Configuration files (mounted as /workspace/config)
│   └── gimprc           # Custom GIMP settings
└── README.md            # This file
```

### 👥 **Multi-User Setup**
- **ga user**: Main VNC user with admin privileges
- **artist user**: Regular user for art creation
- Both users get GIMP configured automatically

### ⚙️ **Custom Configuration**
- Optimized GIMP settings for container/VNC usage
- Desktop shortcuts and launcher scripts
- Sample projects directory structure
- Performance tuning for remote display

## Usage

### Run the Environment
```bash
python -m gym_anything.cli run examples/gimp_env
```

### Connect via VNC
- URL: `vnc://localhost:5950`
- Password: `password`

### Using GIMP
1. **Desktop Shortcut**: Double-click GIMP icon on desktop
2. **Terminal**: Run `gimp` or `launch-gimp` 
3. **Optimized Launch**: Use `/usr/local/bin/launch-gimp` for best performance

## How It Works

### 1. Base Extension Pattern
Instead of writing a Dockerfile from scratch:
```json
{
  "base": "ubuntu-gnome-systemd",
  "hooks": {
    "pre_start": "/workspace/setup/install_gimp.sh",
    "post_start": "/workspace/setup/setup_gimp.sh"
  }
}
```

### 2. Script Mounting
Scripts and config files are mounted into the container:
```json
{
  "mounts": [
    {"source": "examples/gimp_env/scripts", "target": "/workspace/setup"},
    {"source": "examples/gimp_env/config", "target": "/workspace/config"}
  ]
}
```

### 3. Hook Execution
- **pre_start**: Runs during container initialization, installs software
- **post_start**: Runs after services start, configures user environments

## Customization Examples

### Add More Graphics Software
Edit `install_gimp.sh` to install additional packages:
```bash
apt-get install -y \
    blender \
    krita \
    darktable \
    rawtherapee
```

### Auto-start GIMP
Set environment variable in the container:
```bash
export GIMP_AUTO_START=true
```

### Custom Plugins
Add plugin installation to `setup_gimp.sh`:
```bash
# Install custom GIMP plugins
sudo -u ga mkdir -p "/home/ga/.config/GIMP/2.10/plug-ins"
sudo -u ga cp /workspace/config/plugins/* "/home/ga/.config/GIMP/2.10/plug-ins/"
```

## Key Benefits

✅ **No Dockerfile Required**: Extends existing presets with simple scripts  
✅ **Reusable Pattern**: Same approach works for any software  
✅ **Version Control Friendly**: All setup logic in trackable scripts  
✅ **Easy Debugging**: Can modify scripts without rebuilding images  
✅ **Multi-User Aware**: Automatically configures all defined users  

## Software Installed

- **GIMP 2.10+** with help documentation
- **Plugins**: gimp-plugin-registry, gimp-gmic
- **Additional Tools**: Inkscape, ImageMagick, ExifTool
- **Fonts**: Liberation, DejaVu, Noto, Hack, Fira Code
- **Development Tools**: Build tools for compiling additional plugins

## Expanding to Other Software

This pattern works for any software:

1. **Create environment directory** with scripts/ and config/
2. **Set base preset** (ubuntu-gnome-systemd, x11-lite, etc.)
3. **Write installation script** for pre_start hook
4. **Write configuration script** for post_start hook  
5. **Mount scripts and config** into container
6. **Define hooks** in env.json

Examples: VSCode, Blender, game environments, scientific software, etc.
