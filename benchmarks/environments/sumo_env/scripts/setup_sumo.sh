#!/bin/bash
set -e

echo "=== Setting up SUMO environment ==="

# Wait for desktop to be ready
sleep 5

# Set SUMO_HOME
export SUMO_HOME="/usr/share/sumo"

# Create working directories for ga user
echo "Creating working directories..."
sudo -u ga mkdir -p /home/ga/SUMO_Scenarios
sudo -u ga mkdir -p /home/ga/SUMO_Scenarios/bologna_acosta
sudo -u ga mkdir -p /home/ga/SUMO_Scenarios/bologna_pasubio
sudo -u ga mkdir -p /home/ga/SUMO_Output
sudo -u ga mkdir -p /home/ga/Desktop

# Copy real-world Bologna scenario data to user directories
echo "Copying Bologna Acosta scenario..."
cp /workspace/data/bologna_acosta/* /home/ga/SUMO_Scenarios/bologna_acosta/
chown -R ga:ga /home/ga/SUMO_Scenarios/bologna_acosta/

echo "Copying Bologna Pasubio scenario..."
cp /workspace/data/bologna_pasubio/* /home/ga/SUMO_Scenarios/bologna_pasubio/
chown -R ga:ga /home/ga/SUMO_Scenarios/bologna_pasubio/

# Create GUI settings file for Pasubio (it doesn't have one)
cat > /home/ga/SUMO_Scenarios/bologna_pasubio/settings.gui.xml << 'EOF'
<gui-settings>
    <scheme name="real world"></scheme>
</gui-settings>
EOF
chown ga:ga /home/ga/SUMO_Scenarios/bologna_pasubio/settings.gui.xml

# Add gui-settings reference to pasubio sumocfg
cat > /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>

<sumoConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://sumo.dlr.de/xsd/sumoConfiguration.xsd">

    <input>
        <net-file value="pasubio_buslanes.net.xml"/>
        <route-files value="pasubio.rou.xml"/>
        <additional-files value="pasubio_vtypes.add.xml,pasubio_bus_stops.add.xml,pasubio_busses.rou.xml,pasubio_detectors.add.xml,pasubio_tls.add.xml"/>
    </input>

    <output>
        <tripinfo-output value="tripinfos.xml"/>
    </output>

    <report>
        <log value="sumo_log.txt"/>
        <no-step-log value="true"/>
    </report>

    <gui_only>
        <gui-settings-file value="settings.gui.xml"/>
    </gui_only>

</sumoConfiguration>
EOF
chown ga:ga /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg

# Create desktop shortcuts
cat > /home/ga/Desktop/sumo-gui.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=SUMO GUI
Comment=Traffic Simulation GUI
Exec=sumo-gui
Icon=sumo
StartupNotify=true
Terminal=false
Categories=Science;Simulation;
Type=Application
DESKTOPEOF
chown ga:ga /home/ga/Desktop/sumo-gui.desktop
chmod +x /home/ga/Desktop/sumo-gui.desktop

cat > /home/ga/Desktop/netedit.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=SUMO netedit
Comment=Network Editor for SUMO
Exec=netedit
Icon=netedit
StartupNotify=true
Terminal=false
Categories=Science;Simulation;
Type=Application
DESKTOPEOF
chown ga:ga /home/ga/Desktop/netedit.desktop
chmod +x /home/ga/Desktop/netedit.desktop

# Create launch helper scripts
cat > /home/ga/launch_sumo_gui.sh << 'LAUNCHEOF'
#!/bin/bash
export DISPLAY=${DISPLAY:-:1}
export SUMO_HOME=/usr/share/sumo
sumo-gui "$@" > /tmp/sumo_gui.log 2>&1 &
echo "sumo-gui started. Log: /tmp/sumo_gui.log"
LAUNCHEOF
chown ga:ga /home/ga/launch_sumo_gui.sh
chmod +x /home/ga/launch_sumo_gui.sh

cat > /home/ga/launch_netedit.sh << 'LAUNCHEOF'
#!/bin/bash
export DISPLAY=${DISPLAY:-:1}
export SUMO_HOME=/usr/share/sumo
netedit "$@" > /tmp/netedit.log 2>&1 &
echo "netedit started. Log: /tmp/netedit.log"
LAUNCHEOF
chown ga:ga /home/ga/launch_netedit.sh
chmod +x /home/ga/launch_netedit.sh

# Set environment for ga user
cat >> /home/ga/.bashrc << 'BASHRCEOF'
export SUMO_HOME="/usr/share/sumo"
export PATH="$SUMO_HOME/bin:$PATH"
BASHRCEOF
chown ga:ga /home/ga/.bashrc

echo "=== SUMO setup complete ==="
echo "Scenarios available:"
echo "  - Bologna Acosta: /home/ga/SUMO_Scenarios/bologna_acosta/run.sumocfg"
echo "  - Bologna Pasubio: /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg"
echo "Output directory: /home/ga/SUMO_Output/"
