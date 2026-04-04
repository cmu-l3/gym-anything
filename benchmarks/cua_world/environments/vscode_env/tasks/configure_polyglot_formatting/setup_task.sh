#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Multi-Language Formatter Configuration Task ==="

WORKSPACE_DIR="/home/ga/workspace/polyglot_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"

# Create poorly formatted Python file
cat > "$WORKSPACE_DIR/main.py" << 'EOF'
def calculate_sum(a,b,c):
  result=a+b+c
  return result

class DataProcessor:
  def __init__(self,data):
    self.data=data
  
  def process(self):
      for item in self.data:
        print(item)

def main( ):
    processor=DataProcessor([1,2,3,4,5])
    processor.process()
    total=calculate_sum(10,20,30)
    print(f"Total: {total}")

if __name__=="__main__":
  main()
EOF

# Create poorly formatted JavaScript file
cat > "$WORKSPACE_DIR/app.js" << 'EOF'
function fetchData(url){
const response=fetch(url);
return response.json();}

const userData={name:"John",age:30,email:"john@example.com",address:{city:"New York",zip:"10001"}};

if(userData.age>18){console.log("Adult user");}else{console.log("Minor user");}

async function processUser(id){
const user=await fetchData(`/api/users/${id}`);
return{...user,processed:true};}

export default{fetchData,processUser,userData};
EOF

# Create poorly formatted JSON file
cat > "$WORKSPACE_DIR/config.json" << 'EOF'
{"server":{"host":"localhost","port":8080,"ssl":false,"timeout":3000},"database":{"url":"postgresql://localhost/mydb","poolSize":10,"maxConnections":50},"logging":{"level":"info","format":"json","destination":"stdout"},"features":{"enableCache":true,"cacheTimeout":300,"enableMetrics":true}}
EOF

# Create workspace settings with minimal config (no formatters configured yet)
cat > "$WORKSPACE_DIR/.vscode/settings.json" << 'EOF'
{
  "files.autoSave": "afterDelay",
  "editor.fontSize": 14
}
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

echo "Sample files created:"
ls -la "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the main.py file to provide context
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/main.py'" || true

echo "=== Multi-Language Formatter Configuration Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Workspace: $WORKSPACE_DIR"
echo "  Files: main.py (Python), app.js (JavaScript), config.json (JSON)"
echo ""
echo "  Configure language-specific formatters:"
echo "  1. Open Settings JSON (Ctrl+Shift+P → 'Preferences: Open Settings (JSON)')"
echo "  2. Add [python] section with editor.defaultFormatter: 'ms-python.black-formatter'"
echo "  3. Add [javascript] section with editor.defaultFormatter: 'esbenp.prettier-vscode'"
echo "  4. Add [json] section with editor.defaultFormatter: 'esbenp.prettier-vscode'"
echo "  5. Save the settings file"