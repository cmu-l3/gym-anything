#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Save Webpage for Offline Reading Task Setup ==="
echo "Task: Save a complete webpage with all resources for offline access"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip wget || true

# Install Python libraries for verification (beautifulsoup4)
pip3 install -q beautifulsoup4 lxml 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the sample tutorial webpage with embedded resources
echo "Creating sample tutorial webpage..."
TUTORIAL_DIR="/home/ga/Documents/tutorial_content"
mkdir -p "$TUTORIAL_DIR/images"

# Create a simple image (1x1 pixel PNG as base64) for testing
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" | base64 -d > "$TUTORIAL_DIR/images/sample1.png"
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==" | base64 -d > "$TUTORIAL_DIR/images/sample2.png"

# Create CSS file
cat > "$TUTORIAL_DIR/styles.css" << 'EOF'
body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    line-height: 1.8;
    margin: 50px auto;
    max-width: 900px;
    padding: 20px;
    background-color: #f9f9f9;
    color: #333;
}
h1 {
    color: #2c3e50;
    border-bottom: 3px solid #3498db;
    padding-bottom: 10px;
}
h2 {
    color: #34495e;
    margin-top: 30px;
}
.highlight {
    background-color: #fff3cd;
    padding: 15px;
    border-left: 4px solid #ffc107;
    margin: 20px 0;
}
.code-block {
    background-color: #282c34;
    color: #abb2bf;
    padding: 15px;
    border-radius: 5px;
    font-family: 'Courier New', monospace;
    overflow-x: auto;
}
img {
    max-width: 100%;
    height: auto;
    border: 1px solid #ddd;
    padding: 5px;
    margin: 15px 0;
}
.info-box {
    background-color: #e3f2fd;
    padding: 15px;
    border-radius: 5px;
    margin: 20px 0;
}
EOF

# Create the main tutorial HTML
cat > "$TUTORIAL_DIR/python_tutorial.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Python Programming Tutorial - Complete Guide for Beginners</title>
    <link rel="stylesheet" href="styles.css">
    <style>
        /* Additional inline styles for testing mixed CSS */
        .inline-styled {
            font-weight: bold;
            color: #e74c3c;
        }
    </style>
</head>
<body>
    <h1>Python Programming Tutorial: A Complete Beginner's Guide</h1>
    
    <div class="info-box">
        <strong>Note:</strong> This tutorial is designed for complete beginners who want to learn Python programming. 
        Save this page offline to read during your commute or flight!
    </div>
    
    <h2>Introduction to Python</h2>
    <p>Python is a versatile, high-level programming language known for its simplicity and readability. 
    Created by Guido van Rossum and first released in 1991, Python has become one of the most popular 
    programming languages in the world, widely used in web development, data science, artificial intelligence, 
    automation, and scientific computing.</p>
    
    <img src="images/sample1.png" alt="Python Programming Illustration" width="400">
    
    <div class="highlight">
        <strong>Why Learn Python?</strong>
        <ul>
            <li>Easy to learn and read with clean, intuitive syntax</li>
            <li>Extensive standard library and third-party packages</li>
            <li>Strong community support and excellent documentation</li>
            <li>Cross-platform compatibility (Windows, macOS, Linux)</li>
            <li>Excellent for rapid prototyping and development</li>
        </ul>
    </div>
    
    <h2>Getting Started: Installation</h2>
    <p>Before you can start writing Python code, you need to install Python on your computer. Visit the 
    official Python website at <span class="inline-styled">python.org</span> and download the latest version 
    for your operating system. The installation process is straightforward and includes the Python interpreter, 
    standard library, and IDLE (Integrated Development and Learning Environment).</p>
    
    <div class="code-block">
        # Verify Python installation<br>
        $ python --version<br>
        Python 3.11.0<br>
        <br>
        # Open Python interactive shell<br>
        $ python<br>
        >>> print("Hello, World!")<br>
        Hello, World!
    </div>
    
    <h2>Basic Syntax and Data Types</h2>
    <p>Python's syntax is designed to be clean and readable. Unlike many programming languages, Python uses 
    indentation to define code blocks instead of curly braces or keywords. This enforces good coding practices 
    and makes code more readable.</p>
    
    <img src="images/sample2.png" alt="Python Data Types Diagram" width="400">
    
    <h3>Variables and Assignment</h3>
    <p>In Python, you don't need to declare variable types explicitly. The interpreter automatically determines 
    the type based on the assigned value.</p>
    
    <div class="code-block">
        # Variable assignments<br>
        name = "Alice"          # String<br>
        age = 25                # Integer<br>
        height = 5.6            # Float<br>
        is_student = True       # Boolean<br>
        <br>
        # Multiple assignments<br>
        x, y, z = 1, 2, 3<br>
        a = b = c = 0
    </div>
    
    <h3>Common Data Types</h3>
    <p>Python includes several built-in data types that you'll use frequently:</p>
    <ul>
        <li><strong>Strings (str):</strong> Text data enclosed in quotes</li>
        <li><strong>Integers (int):</strong> Whole numbers without decimal points</li>
        <li><strong>Floats (float):</strong> Numbers with decimal points</li>
        <li><strong>Booleans (bool):</strong> True or False values</li>
        <li><strong>Lists:</strong> Ordered, mutable collections</li>
        <li><strong>Tuples:</strong> Ordered, immutable collections</li>
        <li><strong>Dictionaries:</strong> Key-value pairs</li>
        <li><strong>Sets:</strong> Unordered collections of unique elements</li>
    </ul>
    
    <h2>Control Flow: Conditional Statements</h2>
    <p>Control flow statements allow you to execute different code blocks based on conditions.</p>
    
    <div class="code-block">
        # if-elif-else statement<br>
        temperature = 75<br>
        <br>
        if temperature > 80:<br>
        &nbsp;&nbsp;&nbsp;&nbsp;print("It's hot outside!")<br>
        elif temperature > 60:<br>
        &nbsp;&nbsp;&nbsp;&nbsp;print("It's a nice day!")<br>
        else:<br>
        &nbsp;&nbsp;&nbsp;&nbsp;print("It's cold outside!")
    </div>
    
    <h2>Loops: Iteration in Python</h2>
    <p>Loops allow you to execute code repeatedly. Python provides two main loop types: for loops and while loops.</p>
    
    <div class="code-block">
        # For loop example<br>
        fruits = ["apple", "banana", "cherry"]<br>
        for fruit in fruits:<br>
        &nbsp;&nbsp;&nbsp;&nbsp;print(f"I like {fruit}")<br>
        <br>
        # While loop example<br>
        count = 0<br>
        while count < 5:<br>
        &nbsp;&nbsp;&nbsp;&nbsp;print(f"Count: {count}")<br>
        &nbsp;&nbsp;&nbsp;&nbsp;count += 1
    </div>
    
    <h2>Functions: Reusable Code Blocks</h2>
    <p>Functions allow you to organize code into reusable blocks. They help make your code more modular, 
    readable, and maintainable.</p>
    
    <div class="code-block">
        # Function definition<br>
        def greet(name, greeting="Hello"):<br>
        &nbsp;&nbsp;&nbsp;&nbsp;"""Greet someone with a custom message"""<br>
        &nbsp;&nbsp;&nbsp;&nbsp;return f"{greeting}, {name}!"<br>
        <br>
        # Function calls<br>
        print(greet("Alice"))           # Hello, Alice!<br>
        print(greet("Bob", "Hi"))       # Hi, Bob!
    </div>
    
    <div class="highlight">
        <strong>Best Practice:</strong> Always include docstrings in your functions to explain what they do. 
        This makes your code more maintainable and helps other developers (including future you) understand 
        your code's purpose.
    </div>
    
    <h2>Working with Lists and Dictionaries</h2>
    <p>Lists and dictionaries are two of the most commonly used data structures in Python.</p>
    
    <div class="code-block">
        # Lists<br>
        numbers = [1, 2, 3, 4, 5]<br>
        numbers.append(6)           # Add element<br>
        numbers.remove(3)           # Remove element<br>
        <br>
        # List comprehension<br>
        squares = [x**2 for x in range(10)]<br>
        <br>
        # Dictionaries<br>
        person = {<br>
        &nbsp;&nbsp;&nbsp;&nbsp;"name": "Alice",<br>
        &nbsp;&nbsp;&nbsp;&nbsp;"age": 25,<br>
        &nbsp;&nbsp;&nbsp;&nbsp;"city": "New York"<br>
        }<br>
        print(person["name"])       # Access value
    </div>
    
    <h2>Exception Handling</h2>
    <p>Proper error handling makes your programs more robust and user-friendly.</p>
    
    <div class="code-block">
        # Try-except block<br>
        try:<br>
        &nbsp;&nbsp;&nbsp;&nbsp;result = 10 / 0<br>
        except ZeroDivisionError:<br>
        &nbsp;&nbsp;&nbsp;&nbsp;print("Cannot divide by zero!")<br>
        except Exception as e:<br>
        &nbsp;&nbsp;&nbsp;&nbsp;print(f"An error occurred: {e}")<br>
        finally:<br>
        &nbsp;&nbsp;&nbsp;&nbsp;print("Cleanup code here")
    </div>
    
    <h2>File Operations</h2>
    <p>Reading from and writing to files is a common task in programming.</p>
    
    <div class="code-block">
        # Writing to a file<br>
        with open("output.txt", "w") as file:<br>
        &nbsp;&nbsp;&nbsp;&nbsp;file.write("Hello, World!\n")<br>
        <br>
        # Reading from a file<br>
        with open("output.txt", "r") as file:<br>
        &nbsp;&nbsp;&nbsp;&nbsp;content = file.read()<br>
        &nbsp;&nbsp;&nbsp;&nbsp;print(content)
    </div>
    
    <h2>Object-Oriented Programming Basics</h2>
    <p>Python supports object-oriented programming (OOP), which helps organize code into logical, reusable components.</p>
    
    <div class="code-block">
        # Class definition<br>
        class Dog:<br>
        &nbsp;&nbsp;&nbsp;&nbsp;def __init__(self, name, age):<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;self.name = name<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;self.age = age<br>
        <br>
        &nbsp;&nbsp;&nbsp;&nbsp;def bark(self):<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;return f"{self.name} says Woof!"<br>
        <br>
        # Creating an object<br>
        my_dog = Dog("Buddy", 3)<br>
        print(my_dog.bark())
    </div>
    
    <div class="info-box">
        <strong>Next Steps:</strong> Now that you understand the basics, explore Python's extensive ecosystem 
        of libraries and frameworks. Consider learning popular libraries like NumPy for numerical computing, 
        Pandas for data analysis, Django for web development, or TensorFlow for machine learning.
    </div>
    
    <h2>Conclusion</h2>
    <p>This tutorial has covered the fundamental concepts of Python programming, including syntax, data types, 
    control flow, functions, data structures, exception handling, file operations, and object-oriented programming. 
    Python's versatility and extensive ecosystem make it an excellent choice for beginners and experienced 
    developers alike.</p>
    
    <p>Remember, the best way to learn programming is through practice. Try modifying the code examples in this 
    tutorial, experiment with different approaches, and build your own projects. The Python community is welcoming 
    and supportive, with countless resources available for continued learning.</p>
    
    <div class="highlight">
        <strong>Pro Tip:</strong> You saved this page for offline reading, which means you can reference these 
        examples anytime, even without an internet connection. Perfect for coding sessions on planes, trains, 
        or anywhere else!
    </div>
    
    <p><em>Happy coding, and welcome to the Python programming community!</em></p>
</body>
</html>
EOF

chown -R ga:ga "$TUTORIAL_DIR"
echo "✓ Tutorial webpage created at: $TUTORIAL_DIR/python_tutorial.html"

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
# This ensures we're on the first desktop where Chrome is running
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

# Navigate to the tutorial page
TUTORIAL_URL="file:///home/ga/Documents/tutorial_content/python_tutorial.html"
echo "Navigating to: $TUTORIAL_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TUTORIAL_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should be displaying the Python tutorial page"
echo "Agent should now:"
echo "  1. Press Ctrl+S to open Save dialog"
echo "  2. Navigate to Downloads folder (or use default)"
echo "  3. Set filename (e.g., 'python_tutorial_offline')"
echo "  4. IMPORTANT: Select 'Webpage, Complete' format (not 'HTML only')"
echo "  5. Click Save button"
echo ""
echo "The saved page will include both the HTML file and a '_files' folder with all resources"