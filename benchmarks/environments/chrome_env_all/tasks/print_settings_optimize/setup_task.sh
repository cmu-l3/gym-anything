#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Print Settings Optimization Task Setup ==="
echo "Task: Configure print settings for optimized webpage printing"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install PDF processing libraries for verification
pip3 install -q PyPDF2 pypdf pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create a content-rich sample webpage for printing
echo "Creating sample webpage for print optimization..."
ARTICLE_DIR="/home/ga/Documents"
mkdir -p "$ARTICLE_DIR"

cat > "$ARTICLE_DIR/recipe_article.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Classic Chocolate Chip Cookies Recipe</title>
    <style>
        body {
            font-family: Georgia, serif;
            line-height: 1.8;
            margin: 40px;
            max-width: 800px;
            background-color: #f5f5dc;
            background-image: linear-gradient(45deg, #f5f5dc 25%, #fff8dc 25%, #fff8dc 50%, #f5f5dc 50%, #f5f5dc 75%, #fff8dc 75%, #fff8dc);
            background-size: 40px 40px;
        }
        .content {
            background-color: white;
            padding: 30px;
            box-shadow: 0 0 20px rgba(0,0,0,0.1);
        }
        h1 { 
            color: #8b4513; 
            margin-top: 0;
            border-bottom: 3px solid #d2691e;
            padding-bottom: 10px;
        }
        h2 { 
            color: #a0522d; 
            margin-top: 25px;
            border-left: 5px solid #cd853f;
            padding-left: 15px;
        }
        h3 { color: #8b4513; }
        p { margin: 15px 0; text-align: justify; }
        .highlight { 
            background-color: #fffacd; 
            padding: 20px; 
            margin: 20px 0; 
            border-left: 5px solid #ffa500;
        }
        .ingredients {
            background-color: #fff8dc;
            padding: 15px;
            border-radius: 5px;
        }
        ul { line-height: 2; }
        .tip {
            background-color: #e6f3ff;
            padding: 15px;
            margin: 15px 0;
            border-left: 5px solid #4169e1;
        }
    </style>
</head>
<body>
    <div class="content">
        <h1>Classic Chocolate Chip Cookies Recipe</h1>
        
        <p><strong>Prep Time:</strong> 15 minutes | <strong>Cook Time:</strong> 12 minutes | <strong>Total Time:</strong> 27 minutes | <strong>Yield:</strong> 48 cookies</p>

        <h2>Introduction</h2>
        <p>There's nothing quite like the aroma of freshly baked chocolate chip cookies wafting through your home. This classic recipe has been perfected over generations, combining the perfect balance of crispy edges and chewy centers, studded with melty chocolate chips. Whether you're baking for a special occasion or simply satisfying a sweet craving, these cookies never disappoint.</p>

        <p>The secret to truly exceptional chocolate chip cookies lies in the details: room temperature butter for proper creaming, a mix of white and brown sugar for depth of flavor, and the critical step of chilling the dough. Don't skip the chill time—it's what gives these cookies their perfect texture and prevents excessive spreading during baking.</p>

        <div class="ingredients">
            <h2>Ingredients</h2>
            <ul>
                <li>2¼ cups (280g) all-purpose flour</li>
                <li>1 teaspoon baking soda</li>
                <li>1 teaspoon salt</li>
                <li>1 cup (227g) unsalted butter, softened to room temperature</li>
                <li>¾ cup (150g) granulated white sugar</li>
                <li>¾ cup (165g) packed light brown sugar</li>
                <li>2 large eggs, at room temperature</li>
                <li>2 teaspoons pure vanilla extract</li>
                <li>2 cups (340g) semi-sweet chocolate chips</li>
                <li>1 cup (120g) chopped walnuts or pecans (optional)</li>
            </ul>
        </div>

        <h2>Equipment Needed</h2>
        <ul>
            <li>Large mixing bowl</li>
            <li>Electric mixer (stand or hand)</li>
            <li>Medium bowl for dry ingredients</li>
            <li>Baking sheets (2-3 recommended)</li>
            <li>Parchment paper or silicone baking mats</li>
            <li>Cookie scoop or tablespoon</li>
            <li>Wire cooling rack</li>
            <li>Measuring cups and spoons</li>
        </ul>

        <h2>Step-by-Step Instructions</h2>

        <h3>Step 1: Prepare Your Mise en Place</h3>
        <p>Before you begin, make sure your butter and eggs are at room temperature. This is crucial for proper incorporation and texture. Take them out of the refrigerator about 30-45 minutes before you start baking. Room temperature butter should leave a slight indent when pressed but still hold its shape.</p>

        <h3>Step 2: Mix Dry Ingredients</h3>
        <p>In a medium bowl, whisk together the flour, baking soda, and salt. This ensures even distribution of the leavening agent throughout your cookies. Set this mixture aside—you'll add it to the wet ingredients later. The whisking process also aerates the flour slightly, contributing to a lighter texture.</p>

        <h3>Step 3: Cream Butter and Sugars</h3>
        <p>In your large mixing bowl, using an electric mixer on medium-high speed, cream together the softened butter, granulated sugar, and brown sugar for about 3-4 minutes. The mixture should become light and fluffy, with a pale color. This creaming process incorporates air into the dough, which helps create that perfect cookie texture. Don't rush this step—proper creaming is one of the most important techniques in cookie baking.</p>

        <div class="tip">
            <strong>Pro Tip:</strong> The butter-sugar mixture is ready when it looks lighter in color and has a fluffy, whipped appearance. If you under-cream, your cookies will be dense; if you over-cream, they may spread too much during baking.
        </div>

        <h3>Step 4: Add Eggs and Vanilla</h3>
        <p>Beat in the eggs one at a time, mixing well after each addition. Add the vanilla extract and beat until everything is fully incorporated. The mixture might look slightly curdled at this point—that's perfectly normal. Make sure to scrape down the sides and bottom of the bowl with a spatula to ensure all ingredients are evenly mixed.</p>

        <h3>Step 5: Incorporate Dry Ingredients</h3>
        <p>Reduce your mixer speed to low. Gradually add the flour mixture to the wet ingredients, mixing just until no flour streaks remain. Be careful not to overmix at this stage, as this can lead to tough cookies. It's okay if there are a few small flour pockets—they'll incorporate as you add the chocolate chips. Overmixing develops too much gluten, resulting in cookies that are more cake-like than chewy.</p>

        <h3>Step 6: Fold in Chocolate Chips</h3>
        <p>Using a wooden spoon or sturdy spatula, fold in the chocolate chips (and nuts, if using) until they're evenly distributed throughout the dough. This is best done by hand rather than with the mixer to avoid over-working the dough. Make sure every cookie will have plenty of chocolate chips—don't be shy with them!</p>

        <div class="highlight">
            <h3>The Crucial Chilling Step</h3>
            <p>Cover your bowl with plastic wrap and refrigerate the dough for at least 30 minutes, or up to 72 hours. Chilling serves multiple purposes: it solidifies the butter (preventing excessive spreading), allows the flour to fully hydrate (improving texture), and lets the flavors meld together. For the absolute best results, chill for 24-48 hours. Yes, it requires patience, but the difference is remarkable!</p>
        </div>

        <h3>Step 7: Prepare for Baking</h3>
        <p>When you're ready to bake, preheat your oven to 375°F (190°C). Line your baking sheets with parchment paper or silicone baking mats. This prevents sticking and promotes even browning. If you're baking multiple batches, prepare your cookie dough balls on additional sheets of parchment paper for quick transitions between batches.</p>

        <h3>Step 8: Shape and Space the Cookies</h3>
        <p>Using a cookie scoop or tablespoon, portion the dough into rounds about 2 tablespoons each. Roll them gently between your palms to form balls, then place them on the prepared baking sheets, spacing them about 2-3 inches apart. They will spread during baking, so adequate spacing is important. For a bakery-style look, you can place a few extra chocolate chips on top of each dough ball before baking.</p>

        <h3>Step 9: Bake to Perfection</h3>
        <p>Bake for 10-12 minutes, or until the edges are golden brown but the centers still look slightly underdone. This is key—cookies continue to cook on the hot baking sheet after you remove them from the oven (called carryover cooking). If you wait until they look completely done in the oven, they'll be overbaked once they cool. For chewier cookies, aim for 10 minutes; for crispier cookies, go for 12 minutes.</p>

        <div class="tip">
            <strong>Baking Tip:</strong> Rotate your baking sheet 180 degrees halfway through baking for even browning, especially if your oven has hot spots. Also, bake one sheet at a time on the center rack for the most consistent results.
        </div>

        <h3>Step 10: Cool and Enjoy</h3>
        <p>Let the cookies cool on the baking sheet for 5 minutes—this allows them to set and makes them easier to transfer without breaking. Then, using a spatula, carefully move them to a wire cooling rack to cool completely. The cookies will firm up as they cool. For the ultimate indulgence, enjoy them while still slightly warm with a cold glass of milk!</p>

        <h2>Storage and Make-Ahead Tips</h2>
        <p><strong>Room Temperature:</strong> Store cooled cookies in an airtight container at room temperature for up to 1 week. Place a slice of bread in the container to keep cookies soft—the cookies will absorb moisture from the bread.</p>

        <p><strong>Freezing Baked Cookies:</strong> Freeze cookies in a single layer on a baking sheet until solid, then transfer to a freezer-safe container or bag. They'll keep for up to 3 months. Thaw at room temperature for about 30 minutes before serving.</p>

        <p><strong>Freezing Cookie Dough:</strong> Shape dough into balls and freeze on a baking sheet. Once solid, transfer to a freezer bag. Frozen dough balls can be baked directly from the freezer—just add 1-2 minutes to the baking time. This is perfect for having fresh cookies whenever the craving strikes!</p>

        <h2>Variations and Customizations</h2>
        
        <h3>Double Chocolate Chip Cookies</h3>
        <p>Replace ½ cup of flour with ½ cup unsweetened cocoa powder for rich chocolate cookies. Use both semi-sweet and white chocolate chips for extra decadence.</p>

        <h3>Oatmeal Chocolate Chip</h3>
        <p>Reduce flour to 2 cups and add 1 cup old-fashioned rolled oats. This adds wonderful texture and a subtle nutty flavor.</p>

        <h3>Sea Salt Chocolate Chip</h3>
        <p>Sprinkle a small pinch of flaky sea salt on top of each cookie immediately after removing from the oven. The salt enhances the sweetness and adds a gourmet touch.</p>

        <h3>Browned Butter Version</h3>
        <p>Brown the butter in a saucepan before using (you'll need to chill it back to room temperature). This adds an incredible nutty, caramel-like depth of flavor.</p>

        <h2>Troubleshooting Common Issues</h2>

        <p><strong>Cookies spread too much:</strong> Your butter may have been too soft, or you skipped the chilling step. Make sure to chill the dough and use butter that's softened but still cool to the touch.</p>

        <p><strong>Cookies are too cakey:</strong> You may have used too much flour (always spoon flour into measuring cups and level off) or overmixed the dough after adding flour.</p>

        <p><strong>Cookies are too flat and crispy:</strong> You may have undermeasured the flour, or your oven temperature might be too low. Use an oven thermometer to verify accuracy.</p>

        <p><strong>Uneven baking:</strong> Rotate pans halfway through baking, and make sure all cookies are the same size. Bake only one sheet at a time on the center rack.</p>

        <h2>Why This Recipe Works</h2>
        <p>This recipe achieves cookie perfection through several key techniques: the combination of granulated and brown sugar provides both structure and chewiness, while the ratio of butter to sugar creates the ideal spread. The room temperature ingredients emulsify properly, creating a smooth dough that bakes evenly. The chilling step is perhaps most critical—it prevents excessive spreading and allows the flavors to develop fully.</p>

        <p>The slightly underbaked centers give you that coveted chewy texture, while the edges crisp up beautifully. The balance of salt enhances all the flavors, making the chocolate taste even more chocolatey. Every element works together to create cookies that rival any bakery.</p>

        <div class="highlight">
            <h3>Final Thoughts</h3>
            <p>Baking is both a science and an art. While this recipe provides a reliable framework, don't be afraid to make it your own. Experiment with different types of chocolate, add-ins like dried fruit or coconut, or try different extracts. The most important ingredients are patience, attention to detail, and love. Happy baking!</p>
        </div>

        <p><em>Recipe developed and tested by Home Bakers Unite. Last updated: 2025</em></p>
    </div>
</body>
</html>
EOF

chown ga:ga "$ARTICLE_DIR/recipe_article.html"
echo "✓ Recipe webpage created at: $ARTICLE_DIR/recipe_article.html"

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

# Navigate to the recipe article
ARTICLE_URL="file:///home/ga/Documents/recipe_article.html"
echo "Navigating to: $ARTICLE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/recipe_article.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should be displaying the recipe article"
echo ""
echo "Agent should now:"
echo "  1. Press Ctrl+P to open print dialog"
echo "  2. Select 'Save as PDF' as destination"
echo "  3. Expand 'More settings' if needed"
echo "  4. DISABLE 'Headers and footers' (uncheck)"
echo "  5. DISABLE 'Background graphics' (uncheck)"
echo "  6. Set Margins to 'None' or 'Minimum'"
echo "  7. Adjust Scale to 85-100% for optimal fitting"
echo "  8. Review print preview"
echo "  9. Click 'Save' and save as: optimized_print.pdf"
echo ""
echo "These settings will optimize the print output:"
echo "  - Remove URL headers and page numbers"
echo "  - Remove colored backgrounds (save ink)"
echo "  - Maximize content space with minimal margins"
echo "  - Scale content to fit efficiently"