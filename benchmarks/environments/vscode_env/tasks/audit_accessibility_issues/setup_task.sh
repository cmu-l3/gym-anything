#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Accessibility Audit Task ==="

WORKSPACE_DIR="/home/ga/workspace/accessibility_audit"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/components"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/pages"

# Create package.json for realism
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "accessibility-audit-project",
  "version": "1.0.0",
  "description": "Web app requiring accessibility audit",
  "main": "index.js",
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  }
}
EOF

# Component 1: UserProfile.jsx - 2 images without alt
cat > "$WORKSPACE_DIR/src/components/UserProfile.jsx" << 'EOF'
import React from 'react';

export default function UserProfile({ user }) {
  return (
    <div className="user-profile">
      <h2>{user.name}</h2>
      <img src={user.avatar} className="avatar" />
      <p>Email: {user.email}</p>
      <img src={user.badge} className="badge" />
      <button onClick={() => console.log('Edit')}>Edit Profile</button>
    </div>
  );
}
EOF

# Component 2: ProductCard.jsx - 1 image without alt, 2 icon buttons without labels
cat > "$WORKSPACE_DIR/src/components/ProductCard.jsx" << 'EOF'
import React from 'react';

export default function ProductCard({ product }) {
  return (
    <div className="product-card">
      <img src={product.image} className="product-image" />
      <h3>{product.name}</h3>
      <p>${product.price}</p>
      <div className="actions">
        <button className="icon-btn"><span>❤️</span></button>
        <button className="icon-btn"><span>🛒</span></button>
        <button aria-label="View details">View</button>
      </div>
    </div>
  );
}
EOF

# Component 3: ContactForm.jsx - 3 inputs without labels
cat > "$WORKSPACE_DIR/src/pages/ContactForm.jsx" << 'EOF'
import React from 'react';

export default function ContactForm() {
  return (
    <form className="contact-form">
      <h2>Contact Us</h2>
      <input type="text" name="name" placeholder="Your name" />
      <input type="email" name="email" placeholder="Your email" />
      <input type="text" name="subject" placeholder="Subject" />
      <label htmlFor="message">Message</label>
      <textarea id="message" name="message"></textarea>
      <button type="submit">Send Message</button>
    </form>
  );
}
EOF

# Component 4: DecorativeImages.jsx - Images with alt="" (CORRECT - should NOT be flagged)
cat > "$WORKSPACE_DIR/src/components/DecorativeImages.jsx" << 'EOF'
import React from 'react';

export default function Hero() {
  return (
    <div className="hero">
      <h1>Welcome to Our Site</h1>
      <img src="/decorations/swirl-left.svg" alt="" className="decoration" />
      <p>We provide excellent services.</p>
      <img src="/decorations/swirl-right.svg" alt="" className="decoration" />
      <img src="/decorations/pattern.svg" alt="" aria-hidden="true" />
    </div>
  );
}
EOF

# Component 5: Gallery.jsx - 2 more images without alt
cat > "$WORKSPACE_DIR/src/pages/Gallery.jsx" << 'EOF'
import React from 'react';

export default function Gallery({ images }) {
  return (
    <div className="gallery">
      <h2>Photo Gallery</h2>
      <div className="grid">
        {images.map((img, idx) => (
          <div key={idx} className="gallery-item">
            <img src={img.url} className="gallery-image" />
            <p>{img.caption}</p>
          </div>
        ))}
      </div>
      <img src="/logo-footer.png" className="footer-logo" />
    </div>
  );
}
EOF

# Component 6: ValidComponent.jsx - All correctly accessible (NO violations)
cat > "$WORKSPACE_DIR/src/components/ValidComponent.jsx" << 'EOF'
import React from 'react';

export default function ValidComponent() {
  return (
    <div className="accessible-component">
      <img src="/logo.png" alt="Company Logo" />
      <form>
        <label htmlFor="username">Username</label>
        <input id="username" type="text" />
        <button type="submit" aria-label="Submit form">Submit</button>
      </form>
    </div>
  );
}
EOF

# Create README with task instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Accessibility Audit Project

This React application needs an accessibility audit to identify WCAG 2.1 Level AA violations.

## Your Task

Find and document all accessibility issues in the `src/` directory:
- Images without proper alt attributes
- Buttons without accessible names  
- Form inputs without labels

Create a report file: `ACCESSIBILITY_AUDIT.md`

## Important Notes

- Images with `alt=""` (empty string) are decorative and are CORRECT - do not report these
- Only report images that completely lack an alt attribute
- Use VSCode search with regex to find violations efficiently
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Create a violation tracking file for the verifier (not visible to agent)
cat > "$WORKSPACE_DIR/.violations_key.json" << 'EOF'
{
  "missing_alt": [
    {"file": "src/components/UserProfile.jsx", "line": 7, "pattern": "<img src={user.avatar}"},
    {"file": "src/components/UserProfile.jsx", "line": 9, "pattern": "<img src={user.badge}"},
    {"file": "src/components/ProductCard.jsx", "line": 6, "pattern": "<img src={product.image}"},
    {"file": "src/pages/Gallery.jsx", "line": 9, "pattern": "<img src={img.url}"},
    {"file": "src/pages/Gallery.jsx", "line": 14, "pattern": "<img src=\"/logo-footer.png\""}
  ],
  "unlabeled_buttons": [
    {"file": "src/components/ProductCard.jsx", "line": 10, "pattern": "<button className=\"icon-btn\"><span>❤️</span>"},
    {"file": "src/components/ProductCard.jsx", "line": 11, "pattern": "<button className=\"icon-btn\"><span>🛒</span>"}
  ],
  "unlabeled_inputs": [
    {"file": "src/pages/ContactForm.jsx", "line": 7, "pattern": "<input type=\"text\" name=\"name\""},
    {"file": "src/pages/ContactForm.jsx", "line": 8, "pattern": "<input type=\"email\" name=\"email\""},
    {"file": "src/pages/ContactForm.jsx", "line": 9, "pattern": "<input type=\"text\" name=\"subject\""}
  ],
  "decorative_images": [
    {"file": "src/components/DecorativeImages.jsx", "line": 7, "pattern": "alt=\"\""},
    {"file": "src/components/DecorativeImages.jsx", "line": 9, "pattern": "alt=\"\""},
    {"file": "src/components/DecorativeImages.jsx", "line": 10, "pattern": "alt=\"\""}
  ]
}
EOF

sudo chown ga:ga "$WORKSPACE_DIR/.violations_key.json"

# Open VSCode to workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Accessibility Audit Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Use Search panel (Ctrl+Shift+F) with regex to find violations"
echo "  2. Look for: images without alt, buttons without labels, inputs without labels"
echo "  3. Remember: alt=\"\" is CORRECT (decorative images) - don't report these"
echo "  4. Create ACCESSIBILITY_AUDIT.md in workspace root with your findings"
echo "  5. Include file paths, line numbers, and categorize by violation type"