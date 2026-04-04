#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Print-to-PDF Task Setup ==="
echo "Task: Print webpage to PDF with landscape orientation and minimal margins"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install PDF processing libraries
pip3 install -q PyPDF2 pypdf pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the sample article HTML file
echo "Creating sample article HTML..."
ARTICLE_DIR="/home/ga/Documents"
mkdir -p "$ARTICLE_DIR"

cat > "$ARTICLE_DIR/machine_learning_article.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Machine Learning Fundamentals</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 40px;
            max-width: 1200px;
        }
        h1 { color: #2c3e50; margin-top: 20px; }
        h2 { color: #34495e; margin-top: 15px; }
        p { margin: 10px 0; text-align: justify; }
        .highlight { background-color: #f0f0f0; padding: 15px; margin: 15px 0; }
    </style>
</head>
<body>
    <h1>Machine Learning Fundamentals: A Comprehensive Guide</h1>
    
    <h2>Introduction to Machine Learning</h2>
    <p>Machine learning is a subset of artificial intelligence that enables systems to learn and improve from experience without being explicitly programmed. This revolutionary approach has transformed how we solve complex problems across various domains, from healthcare to finance, and from autonomous vehicles to recommendation systems.</p>
    
    <p>At its core, machine learning involves training algorithms on data to identify patterns and make predictions. The process begins with collecting and preparing training data, selecting appropriate algorithms, and iteratively improving model performance through validation and testing.</p>

    <h2>Types of Machine Learning</h2>
    
    <h3>Supervised Learning</h3>
    <p>Supervised learning is the most common paradigm in machine learning. In this approach, algorithms learn from labeled training data to make predictions on new, unseen data. Common supervised learning tasks include classification (predicting discrete categories) and regression (predicting continuous values).</p>
    
    <p>Popular supervised learning algorithms include linear regression, logistic regression, decision trees, random forests, support vector machines, and neural networks. Each algorithm has its strengths and is suited for different types of problems and data characteristics.</p>

    <h3>Unsupervised Learning</h3>
    <p>Unsupervised learning algorithms work with unlabeled data to discover hidden patterns and structures. Clustering algorithms group similar data points together, while dimensionality reduction techniques compress data while preserving important information. Principal Component Analysis (PCA) and k-means clustering are classic examples of unsupervised learning methods.</p>

    <h3>Reinforcement Learning</h3>
    <p>Reinforcement learning involves agents learning to make decisions by interacting with an environment. The agent receives rewards or penalties based on its actions and learns to maximize cumulative rewards over time. This approach has achieved remarkable success in game playing, robotics, and autonomous systems.</p>

    <h2>Neural Networks and Deep Learning</h2>
    <p>Neural networks are computational models inspired by biological neural networks in animal brains. They consist of interconnected nodes (neurons) organized in layers. Deep learning refers to neural networks with multiple hidden layers, enabling them to learn hierarchical representations of data.</p>

    <p>Convolutional Neural Networks (CNNs) excel at image processing tasks, while Recurrent Neural Networks (RNNs) and their variants like LSTMs are designed for sequential data such as text and time series. Transformer architectures have recently revolutionized natural language processing with models like GPT and BERT.</p>

    <div class="highlight">
        <h3>Key Concepts in Model Training</h3>
        <p><strong>Training Data:</strong> The dataset used to train the model and learn patterns.</p>
        <p><strong>Validation Data:</strong> Used to tune hyperparameters and prevent overfitting.</p>
        <p><strong>Test Data:</strong> Held-out data used to evaluate final model performance.</p>
        <p><strong>Loss Function:</strong> Measures how well the model's predictions match actual values.</p>
        <p><strong>Optimization:</strong> Process of adjusting model parameters to minimize loss.</p>
    </div>

    <h2>Model Evaluation and Metrics</h2>
    <p>Evaluating machine learning models requires appropriate metrics. For classification tasks, accuracy, precision, recall, F1-score, and ROC-AUC are commonly used. Regression models are typically evaluated using Mean Squared Error (MSE), Root Mean Squared Error (RMSE), and R-squared.</p>

    <p>Cross-validation techniques help ensure models generalize well to unseen data. K-fold cross-validation splits data into multiple subsets, training and validating the model on different combinations to obtain robust performance estimates.</p>

    <h2>Feature Engineering and Selection</h2>
    <p>Feature engineering involves creating new input variables from existing data to improve model performance. This process requires domain knowledge and creativity. Techniques include polynomial features, interaction terms, binning, encoding categorical variables, and extracting features from text or images.</p>

    <p>Feature selection identifies the most relevant input variables, reducing dimensionality and improving model interpretability. Methods include filter methods (statistical tests), wrapper methods (using model performance), and embedded methods (built into the algorithm).</p>

    <h2>Challenges and Best Practices</h2>
    <p>Overfitting occurs when models perform well on training data but poorly on new data. Regularization techniques like L1 and L2 penalties, dropout, and early stopping help prevent overfitting. Underfitting happens when models are too simple to capture data patterns.</p>

    <p>Data quality is paramount in machine learning. Issues like missing values, outliers, imbalanced classes, and biased data can significantly impact model performance. Careful data preprocessing and augmentation strategies are essential for building robust models.</p>

    <h2>Applications Across Industries</h2>
    <p>Machine learning has diverse applications: fraud detection in banking, medical diagnosis in healthcare, demand forecasting in retail, personalized recommendations in e-commerce, predictive maintenance in manufacturing, and sentiment analysis in social media. The technology continues to expand into new domains, solving increasingly complex real-world problems.</p>

    <h2>Ethical Considerations</h2>
    <p>As machine learning systems become more prevalent, ethical considerations are crucial. Issues include algorithmic bias, privacy concerns, transparency and explainability, accountability, and the societal impact of automation. Responsible AI development requires addressing these challenges through careful design, testing, and governance.</p>

    <h2>Future Directions</h2>
    <p>The field of machine learning continues to evolve rapidly. Emerging trends include few-shot and zero-shot learning, federated learning for privacy-preserving model training, AutoML for automated model selection and hyperparameter tuning, and the integration of symbolic reasoning with neural networks. Quantum machine learning and neuromorphic computing represent frontier areas with potential to revolutionize the field.</p>

    <h2>Conclusion</h2>
    <p>Machine learning has become an indispensable tool in modern technology, driving innovation across industries. Understanding fundamental concepts, algorithms, and best practices is essential for practitioners. As the field advances, staying current with new techniques while maintaining ethical considerations will be key to harnessing machine learning's full potential for societal benefit.</p>

</body>
</html>
EOF

chown ga:ga "$ARTICLE_DIR/machine_learning_article.html"
echo "✓ Article HTML created at: $ARTICLE_DIR/machine_learning_article.html"

# Ensure Chrome is properly focused and on correct URL
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

# Navigate to the article
ARTICLE_URL="file:///home/ga/Documents/machine_learning_article.html"
echo "Navigating to: $ARTICLE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/machine_learning_article.html'" || true
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
echo "Chrome should be displaying the Machine Learning article"
echo "Agent should now:"
echo "  1. Press Ctrl+P to open print dialog"
echo "  2. Select 'Save as PDF' as destination"
echo "  3. Choose Landscape orientation"
echo "  4. Set margins to None or Minimum"
echo "  5. Ensure scale is at 100%"
echo "  6. Save as: machine_learning_fundamentals.pdf"