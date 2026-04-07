#!/bin/bash
set -e

echo "=== Installing Tcl/Tk Environment ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Tcl/Tk core packages
apt-get install -y \
    tcl8.6 \
    tk8.6 \
    tcllib \
    tklib

# Install UI automation, screenshot tools, and text editor
apt-get install -y \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    x11-utils \
    python3-pip \
    gedit

# Verify installation
if [ -x "/usr/bin/tclsh8.6" ]; then
    echo "tclsh8.6 installed at /usr/bin/tclsh8.6"
    # Create convenience symlinks
    ln -sf /usr/bin/tclsh8.6 /usr/local/bin/tclsh
    ln -sf /usr/bin/wish8.6 /usr/local/bin/wish
else
    echo "FATAL: Tcl installation failed"
    exit 1
fi

if [ -x "/usr/bin/wish8.6" ]; then
    echo "wish8.6 installed at /usr/bin/wish8.6"
else
    echo "FATAL: Tk installation failed"
    exit 1
fi

# Verify Tk demos are available
if [ -d "/usr/share/tcltk/tk8.6/demos" ]; then
    DEMO_COUNT=$(ls /usr/share/tcltk/tk8.6/demos/*.tcl 2>/dev/null | wc -l)
    echo "Tk demos found at /usr/share/tcltk/tk8.6/demos/ ($DEMO_COUNT .tcl files)"
elif [ -d "/usr/share/tk8.6/demos" ]; then
    DEMO_COUNT=$(ls /usr/share/tk8.6/demos/*.tcl 2>/dev/null | wc -l)
    echo "Tk demos found at /usr/share/tk8.6/demos/ ($DEMO_COUNT .tcl files)"
else
    echo "WARNING: Tk demos directory not found"
fi

echo "Tcl version: $(tclsh8.6 << 'EOF'
puts [info patchlevel]
EOF
)"

echo "=== Tcl/Tk installation complete ==="
