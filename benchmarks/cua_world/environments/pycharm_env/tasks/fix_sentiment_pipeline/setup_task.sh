#!/bin/bash
echo "=== Setting up fix_sentiment_pipeline task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_sentiment_pipeline"
PROJECT_DIR="/home/ga/PycharmProjects/sentiment_pipeline"
HIDDEN_DIR="/var/lib/sentiment_pipeline"

# Clean up previous run
rm -rf "$PROJECT_DIR"
rm -rf "$HIDDEN_DIR"
rm -f /tmp/${TASK_NAME}_*

# Create directories
su - ga -c "mkdir -p $PROJECT_DIR/data $PROJECT_DIR/pipeline $PROJECT_DIR/tests"
mkdir -p "$HIDDEN_DIR"

# Install dependencies
pip3 install scikit-learn pandas pytest > /dev/null 2>&1

# ==============================================================================
# 1. Create Data
# ==============================================================================

# Visible sample data
cat > "$PROJECT_DIR/data/reviews.csv" << 'CSVEOF'
text,sentiment
"This product is amazing and I love it",Positive
"Truly spectacular performance and great design",Positive
"I am very happy with this purchase",Positive
"Works perfectly and looks beautiful",Positive
"Best investment I have made in years",Positive
"Not good at all",Negative
"This is bad very bad",Negative
"I hate this it is terrible",Negative
"Do not buy this waste of money",Negative
"Poor quality and broke immediately",Negative
"Just okay nothing special",Positive
"It is fine I guess",Positive
"Absolutely horrible experience",Negative
"Not happy with the service",Negative
"Great support team",Positive
"Slow shipping but good item",Positive
"The worst thing ever",Negative
"Highly recommended for everyone",Positive
"Not worth the price",Negative
"I like it a lot",Positive
CSVEOF

# Hidden ground truth data (for evaluation)
cat > "$HIDDEN_DIR/hidden_test.csv" << 'CSVEOF'
text,sentiment
"The interface is confusing and not intuitive",Negative
"I am not satisfied with the quality",Negative
"Simply fantastic results every time",Positive
"Sad to see such poor workmanship",Negative
"Excellent build quality and features",Positive
"Not a good experience overall",Negative
"Very bad customer service",Negative
"I absolutely love this widget",Positive
"Terrible waste of time",Negative
"Joy to use every single day",Positive
"Not what I expected at all",Negative
"Ugly and does not work",Negative
"Beautiful finish and fast performance",Positive
"Glad I bought this one",Positive
"No regrets purchasing this",Positive
"Avoid this product at all costs",Negative
"Startlingly good for the price",Positive
"Disappointed by the lack of features",Negative
"Not working as advertised",Negative
"Superb value for money",Positive
CSVEOF
chmod 644 "$HIDDEN_DIR/hidden_test.csv"

# ==============================================================================
# 2. Create Source Code (With Bugs)
# ==============================================================================

# pipeline/__init__.py
touch "$PROJECT_DIR/pipeline/__init__.py"

# pipeline/preprocess.py (BUG 1: Removes negation words)
cat > "$PROJECT_DIR/pipeline/preprocess.py" << 'PYEOF'
import re
from sklearn.feature_extraction.text import ENGLISH_STOP_WORDS

def clean_text(text: str) -> str:
    """
    Clean and preprocess text for sentiment analysis.
    Removes special characters, converts to lowercase, and removes stopwords.
    """
    # Convert to lowercase
    text = text.lower()
    
    # Remove special characters
    text = re.sub(r'[^a-z\s]', '', text)
    
    # Tokenize
    tokens = text.split()
    
    # Remove stopwords
    # BUG: standard list includes 'not', 'no', 'nor', 'never' which flips sentiment
    stop_words = list(ENGLISH_STOP_WORDS)
    
    clean_tokens = [t for t in tokens if t not in stop_words]
    
    return " ".join(clean_tokens)
PYEOF

# pipeline/features.py (BUG 2: Token pattern ignores short words < 5 chars)
cat > "$PROJECT_DIR/pipeline/features.py" << 'PYEOF'
from sklearn.feature_extraction.text import TfidfVectorizer
from pipeline.preprocess import clean_text

class SentimentVectorizer:
    def __init__(self):
        # BUG: token_pattern matches only words with 5 or more characters
        # This ignores crucial words like "bad", "sad", "good", "poor", "hate", "love"
        self.vectorizer = TfidfVectorizer(
            preprocessor=clean_text,
            token_pattern=r'\b[a-zA-Z]{5,}\b',
            max_features=1000
        )
        
    def fit_transform(self, texts):
        return self.vectorizer.fit_transform(texts)
        
    def transform(self, texts):
        return self.vectorizer.transform(texts)
PYEOF

# pipeline/classifier.py (BUG 3: Inverted logic)
cat > "$PROJECT_DIR/pipeline/classifier.py" << 'PYEOF'
import pandas as pd
from sklearn.linear_model import LogisticRegression
from pipeline.features import SentimentVectorizer

class SentimentClassifier:
    def __init__(self):
        self.vectorizer = SentimentVectorizer()
        self.model = LogisticRegression(random_state=42)
        
    def train(self, csv_path):
        df = pd.read_csv(csv_path)
        X = self.vectorizer.fit_transform(df['text'])
        y = (df['sentiment'] == 'Positive').astype(int)
        self.model.fit(X, y)
        
    def predict(self, text):
        """Returns 'Positive' or 'Negative'"""
        X = self.vectorizer.transform([text])
        # Get probability of class 1 (Positive)
        prob_positive = self.model.predict_proba(X)[0][1]
        
        # BUG: Logic is inverted. Usually prob > 0.5 means Positive.
        # Here it returns Positive if prob < 0.5
        if prob_positive < 0.5:
            return "Positive"
        else:
            return "Negative"
PYEOF

# ==============================================================================
# 3. Create Tests
# ==============================================================================

cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
import pandas as pd
import os

@pytest.fixture
def sample_data_path():
    return os.path.join(os.path.dirname(__file__), '../data/reviews.csv')
PYEOF

cat > "$PROJECT_DIR/tests/test_preprocess.py" << 'PYEOF'
from pipeline.preprocess import clean_text

def test_negation_preservation():
    """Test that negation words are preserved during preprocessing."""
    text = "This is not good"
    cleaned = clean_text(text)
    assert "not" in cleaned, f"Negation 'not' was removed! Result: {cleaned}"
    
def test_no_preservation():
    """Test that 'no' is preserved."""
    text = "There is no way"
    cleaned = clean_text(text)
    assert "no" in cleaned, f"Negation 'no' was removed! Result: {cleaned}"
PYEOF

cat > "$PROJECT_DIR/tests/test_features.py" << 'PYEOF'
from pipeline.features import SentimentVectorizer

def test_short_words_included():
    """Test that short but important words are included in the vocabulary."""
    vect = SentimentVectorizer()
    texts = ["bad", "sad", "good", "hate", "love"]
    vect.fit_transform(texts)
    
    vocab = vect.vectorizer.vocabulary_
    
    missing = [w for w in texts if w not in vocab]
    assert not missing, f"Important short words excluded from vocabulary: {missing}"
PYEOF

cat > "$PROJECT_DIR/tests/test_integration.py" << 'PYEOF'
from pipeline.classifier import SentimentClassifier

def test_prediction_logic(sample_data_path):
    """Test end-to-end prediction on obvious cases."""
    clf = SentimentClassifier()
    clf.train(sample_data_path)
    
    # Test positive case
    assert clf.predict("This is amazing and great") == "Positive"
    
    # Test negative case (requires negation handling + short words + correct logic)
    assert clf.predict("This is not good") == "Negative"
    
    # Test short emphatic negative
    assert clf.predict("bad") == "Negative"
PYEOF

# ==============================================================================
# 4. Create Evaluation Script (Hidden from Agent)
# ==============================================================================

cat > "$HIDDEN_DIR/evaluate_model.py" << 'PYEOF'
import sys
import pandas as pd
from sklearn.metrics import f1_score, accuracy_score

# Add project to path
sys.path.append('/home/ga/PycharmProjects/sentiment_pipeline')

try:
    from pipeline.classifier import SentimentClassifier
    
    # Train on visible data
    clf = SentimentClassifier()
    clf.train('/home/ga/PycharmProjects/sentiment_pipeline/data/reviews.csv')
    
    # Test on hidden data
    test_df = pd.read_csv('/var/lib/sentiment_pipeline/hidden_test.csv')
    
    predictions = []
    for text in test_df['text']:
        predictions.append(clf.predict(text))
        
    y_true = test_df['sentiment']
    y_pred = predictions
    
    acc = accuracy_score(y_true, y_pred)
    f1 = f1_score(y_true, y_pred, pos_label='Positive')
    
    print(f"ACCURACY:{acc}")
    print(f"F1:{f1}")
    
except Exception as e:
    print(f"ERROR:{e}")
PYEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Launch PyCharm
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /tmp/pycharm.log 2>&1 &"

# Wait for PyCharm
wait_for_pycharm 60

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "$(date +%s)" > /tmp/task_start_time
echo "=== Setup complete ==="