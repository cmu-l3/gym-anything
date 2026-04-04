#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Page Translation Task Setup ==="
echo "Task: Translate a Spanish webpage to English using Chrome's built-in translation"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install language detection library
pip3 install -q langdetect 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create a Spanish article HTML file for translation
echo "Creating Spanish article HTML..."
ARTICLE_DIR="/home/ga/Documents"
mkdir -p "$ARTICLE_DIR"

cat > "$ARTICLE_DIR/spanish_article.html" << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>La Revolución de la Inteligencia Artificial</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 40px;
            max-width: 800px;
        }
        h1 { color: #2c3e50; }
        h2 { color: #34495e; margin-top: 20px; }
        p { margin: 10px 0; text-align: justify; }
    </style>
</head>
<body>
    <h1>La Revolución de la Inteligencia Artificial</h1>
    
    <h2>Introducción</h2>
    <p>La inteligencia artificial está transformando el mundo de maneras que apenas comenzamos a comprender. Desde asistentes virtuales hasta vehículos autónomos, la tecnología de IA está cambiando la forma en que vivimos y trabajamos.</p>
    
    <h2>Aplicaciones Actuales</h2>
    <p>Hoy en día, la inteligencia artificial se utiliza en medicina para diagnosticar enfermedades, en finanzas para detectar fraudes, y en educación para personalizar el aprendizaje. Los algoritmos de aprendizaje automático pueden analizar grandes cantidades de datos mucho más rápido que cualquier humano.</p>
    
    <h2>El Futuro de la IA</h2>
    <p>Los expertos predicen que la inteligencia artificial continuará evolucionando rápidamente. En los próximos años, veremos avances en áreas como el procesamiento del lenguaje natural, la visión por computadora y la robótica. Estos desarrollos tienen el potencial de resolver algunos de los problemas más desafiantes de la humanidad.</p>
    
    <h2>Desafíos Éticos</h2>
    <p>Sin embargo, el desarrollo de la inteligencia artificial también plantea importantes cuestiones éticas. ¿Cómo garantizamos que la IA sea justa y no discriminatoria? ¿Qué sucede con el empleo cuando las máquinas pueden realizar tareas humanas? ¿Cómo protegemos la privacidad en un mundo impulsado por datos?</p>
    
    <h2>Conclusión</h2>
    <p>La inteligencia artificial representa tanto una oportunidad como un desafío para nuestra sociedad. Es fundamental que desarrollemos esta tecnología de manera responsable, considerando no solo sus capacidades técnicas, sino también su impacto en la sociedad y el bienestar humano.</p>
    
    <p><strong>Palabras clave:</strong> inteligencia artificial, tecnología, futuro, ética, aprendizaje automático</p>
</body>
</html>
EOF

chown ga:ga "$ARTICLE_DIR/spanish_article.html"
echo "✓ Spanish article created at: $ARTICLE_DIR/spanish_article.html"

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Ensure Chrome's translation feature is enabled in Preferences
echo "Configuring Chrome translation settings..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

# Backup and modify Preferences to ensure translation is enabled
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" "$CHROME_PROFILE/Preferences.backup" || true
    
    # Use Python to modify JSON (more reliable than jq for complex nested structures)
    python3 << 'PYTHON_EOF'
import json
import sys

prefs_path = "/home/ga/.config/google-chrome-cdp/Default/Preferences"
try:
    with open(prefs_path, 'r') as f:
        prefs = json.load(f)
    
    # Ensure translate is enabled
    if 'translate' not in prefs:
        prefs['translate'] = {}
    prefs['translate']['enabled'] = True
    
    # Ensure translate_accepted_count is set (makes Chrome more likely to offer translation)
    if 'translate_accepted_count' not in prefs.get('translate', {}):
        prefs['translate']['translate_accepted_count'] = {}
    
    with open(prefs_path, 'w') as f:
        json.dump(prefs, f, indent=2)
    
    print("✓ Translation feature enabled in Chrome preferences")
except Exception as e:
    print(f"⚠ Warning: Could not modify preferences: {e}", file=sys.stderr)
PYTHON_EOF
fi

# Navigate to the Spanish article
ARTICLE_URL="file:///home/ga/Documents/spanish_article.html"
echo "Navigating to Spanish article: $ARTICLE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/spanish_article.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Extract and save original Spanish content for verification
echo "Extracting original Spanish content..."
mkdir -p /tmp/translate_verification

# Use CDP to execute JavaScript and get page text
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    # Get the active tab's WebSocket URL
    ACTIVE_TAB=$(curl -s http://localhost:9222/json | jq -r '[.[] | select(.type == "page")][0]')
    
    # For simplicity, we'll save the initial URL and let verifier know it's Spanish
    echo "$ARTICLE_URL" > /tmp/translate_verification/original_url.txt
    echo "es" > /tmp/translate_verification/original_language.txt
    
    # Extract text content using JavaScript console via CDP (simplified approach)
    # In a real implementation, we'd use CDP WebSocket to execute JS
    # For now, we'll rely on the verifier comparing the source file
    cp "$ARTICLE_DIR/spanish_article.html" /tmp/translate_verification/original_content.html
    
    echo "✓ Original content saved for verification"
fi

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Current URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the Spanish article"
echo "Agent should:"
echo "  1. Wait for Chrome's translation prompt (or trigger via right-click)"
echo "  2. Click 'Translate to English' or similar option"
echo "  3. Verify page content changes to English"
echo ""
echo "Alternative methods:"
echo "  - Right-click page → 'Translate to English'"
echo "  - Click translation icon in address bar"
echo "  - Use Chrome menu → Translate"