#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Encoding Issue Task ==="

WORKSPACE_DIR="/home/ga/workspace/encoding_project"
SCRIPT_FILE="$WORKSPACE_DIR/analyze_data.py"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"

echo "Creating Python file with Windows-1252 encoding..."

# First create the file in UTF-8 with French characters
cat > /tmp/analyze_data_utf8.py << 'PYEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script d'analyse de données
Créé par: Jean-François Martin
Date: été 2024

Ce script analyse les données météorologiques françaises.
"""

def analyser_données(fichier):
    """
    Analyse les données météo.
    
    Args:
        fichier: Chemin vers le fichier de données
        
    Returns:
        Dictionnaire avec température, précipitations
    """
    print("Démarrage de l'analyse...")
    
    # Données de test avec caractères accentués
    villes = ["Paris", "Montréal", "Bruxelles", "Genève"]
    températures = {
        "été": [25, 22, 24, 23],
        "hiver": [5, -10, 3, 0]
    }
    
    # Message de statut
    statut = "Données chargées avec succès !"
    
    return {
        "villes": villes,
        "temp": températures,
        "message": statut
    }


def afficher_résumé(données):
    """Affiche un résumé des données analysées."""
    print("=" * 50)
    print("RÉSUMÉ DE L'ANALYSE")
    print("=" * 50)
    print(f"Villes analysées: {', '.join(données['villes'])}")
    print(f"Saisons: été, hiver")
    print("\nAnalyse terminée avec succès !")


if __name__ == "__main__":
    # Chemin du fichier de données
    fichier_données = "/path/to/données_météo.csv"
    
    # Exécuter l'analyse
    résultats = analyser_données(fichier_données)
    afficher_résumé(résultats)
PYEOF

# Convert UTF-8 file to Windows-1252 encoding to simulate the problem
# This will make French accented characters appear garbled when opened as UTF-8
iconv -f UTF-8 -t WINDOWS-1252 /tmp/analyze_data_utf8.py > "$SCRIPT_FILE"

# Ensure proper ownership
sudo chown ga:ga "$SCRIPT_FILE"
chmod 644 "$SCRIPT_FILE"

echo "File created with Windows-1252 encoding at: $SCRIPT_FILE"
echo "When opened as UTF-8 (default), French characters will appear garbled."

# Create a reference UTF-8 version for verification
sudo -u ga cp /tmp/analyze_data_utf8.py /tmp/analyze_data_reference.py

# Clean up temp file
rm /tmp/analyze_data_utf8.py

# Open VSCode with the problematic file
echo "Opening VSCode with the file..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$SCRIPT_FILE'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Fix Encoding Issue Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Notice garbled French characters in analyze_data.py"
echo "  2. Click encoding indicator in status bar (bottom-right)"
echo "  3. Select 'Reopen with Encoding'"
echo "  4. Choose 'Western (Windows 1252)'"
echo "  5. Verify French text is now readable"
echo "  6. Click encoding indicator again"
echo "  7. Select 'Save with Encoding' → 'UTF-8'"
echo "  8. Save file (Ctrl+S)"