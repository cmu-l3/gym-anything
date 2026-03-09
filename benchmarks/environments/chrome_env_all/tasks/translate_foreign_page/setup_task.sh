#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Foreign Language Translation Task Setup ==="
echo "Task: Translate Japanese webpage to English using Chrome's built-in translation"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests || true

# Wait for environment to be ready
sleep 2

# Create the Japanese article HTML file
echo "Creating Japanese language article HTML..."
ARTICLE_DIR="/home/ga/Documents"
mkdir -p "$ARTICLE_DIR"

cat > "$ARTICLE_DIR/japanese_tech_article.html" << 'EOF'
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="content-language" content="ja">
    <title>最新テクノロジーニュース - 人工知能の進歩</title>
    <style>
        body {
            font-family: 'Hiragino Kaku Gothic Pro', 'Yu Gothic', 'Meiryo', sans-serif;
            line-height: 1.8;
            margin: 40px;
            max-width: 900px;
            background-color: #f5f5f5;
            color: #333;
        }
        .container {
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 { 
            color: #2c3e50; 
            margin-top: 0;
            font-size: 28px;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        h2 { 
            color: #34495e; 
            margin-top: 25px;
            font-size: 22px;
        }
        p { 
            margin: 15px 0; 
            text-align: justify;
        }
        .highlight { 
            background-color: #fffacd; 
            padding: 15px; 
            margin: 20px 0;
            border-left: 4px solid #f39c12;
        }
        .date {
            color: #7f8c8d;
            font-size: 14px;
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>人工知能技術の最新動向と未来への展望</h1>
        <div class="date">2024年1月15日 | テクノロジー部門</div>
        
        <h2>はじめに</h2>
        <p>人工知能（AI）技術は、近年急速に発展し、私たちの日常生活やビジネスシーンに大きな影響を与えています。機械学習、深層学習、自然言語処理などの分野で目覚ましい進歩が見られ、これまで人間にしかできなかった複雑なタスクを自動化することが可能になってきました。</p>
        
        <p>本記事では、最新の人工知能技術の動向と、それが社会に与える影響について詳しく解説します。特に、大規模言語モデルの発展、画像認識技術の向上、そして産業界での実用化事例に焦点を当てます。</p>

        <h2>大規模言語モデルの革新</h2>
        <p>最近の大規模言語モデルは、数千億のパラメータを持ち、人間のような自然な会話や文章生成が可能になりました。これらのモデルは、膨大なテキストデータから学習し、文脈を理解して適切な応答を生成することができます。</p>
        
        <p>ビジネスの現場では、カスタマーサポートの自動化、文書作成の支援、コード生成など、様々な用途で活用されています。教育分野でも、個別最適化された学習支援ツールとして注目を集めています。</p>

        <div class="highlight">
            <strong>注目ポイント：</strong>
            大規模言語モデルは、翻訳、要約、質問応答など、多様な自然言語処理タスクを単一のモデルで実行できる汎用性を持っています。
        </div>

        <h2>コンピュータビジョンの進化</h2>
        <p>画像認識と物体検出の技術も大きく進歩しました。深層学習を用いた画像処理アルゴリズムは、医療画像診断、自動運転車の環境認識、製造業における品質検査など、幅広い分野で実用化されています。</p>
        
        <p>特に、医療分野では、X線画像やCTスキャンから病変を自動的に検出するシステムが開発され、医師の診断を補助する重要なツールとなっています。これにより、診断の精度向上と早期発見が期待されています。</p>

        <h2>自動運転技術の現状</h2>
        <p>自動運転技術は、複数のセンサーとAIを組み合わせることで、周囲の環境を認識し、安全な運転判断を行います。カメラ、LiDAR、レーダーなどから得られる情報を統合処理し、歩行者、他の車両、交通標識などを識別します。</p>
        
        <p>現在、一部の自動車メーカーでは、高速道路での自動運転機能が実用化されており、将来的には完全自動運転の実現が期待されています。これにより、交通事故の削減や移動の効率化が見込まれます。</p>

        <h2>産業界での実用化事例</h2>
        <p>製造業では、AIを活用した予知保全システムが導入され、機械の故障を事前に予測することで、生産ラインの停止を防ぎ、メンテナンスコストを削減しています。また、需要予測や在庫最適化にもAIが活用されています。</p>
        
        <p>金融業界では、不正検知システムや与信審査の自動化、アルゴリズム取引など、様々な分野でAI技術が導入されています。これにより、業務効率の向上とリスク管理の強化が実現されています。</p>

        <h2>倫理的課題と今後の展望</h2>
        <p>AI技術の発展に伴い、プライバシー保護、アルゴリズムの公平性、雇用への影響など、様々な倫理的課題が浮き彫りになっています。これらの課題に対処するため、AI倫理ガイドラインの策定や、説明可能なAIの開発が進められています。</p>
        
        <p>今後、AI技術はさらに進化し、社会のあらゆる場面で活用されることが予想されます。人間とAIが協調して働く新しい社会の実現に向けて、技術開発と同時に、倫理的・社会的な議論を深めていくことが重要です。</p>

        <h2>まとめ</h2>
        <p>人工知能技術は、私たちの生活を大きく変える可能性を秘めています。技術の進歩を適切に管理し、社会全体の利益につながるように活用していくことが、今後の重要な課題となるでしょう。教育、医療、産業など、あらゆる分野でAIの恩恵を受けられる社会を目指して、継続的な研究開発と議論が必要です。</p>
    </div>
</body>
</html>
EOF

chown ga:ga "$ARTICLE_DIR/japanese_tech_article.html"
echo "✓ Japanese article HTML created at: $ARTICLE_DIR/japanese_tech_article.html"

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

# Navigate to the Japanese article
ARTICLE_URL="file:///home/ga/Documents/japanese_tech_article.html"
echo "Navigating to: $ARTICLE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/japanese_tech_article.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Wait a bit more for page to fully load and Chrome to potentially show translation bar
sleep 2

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Check initial page language
    ACTIVE_TAB=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "Active tab URL: $ACTIVE_TAB"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should be displaying the Japanese article"
echo "Agent should now:"
echo "  1. Recognize the page is in Japanese"
echo "  2. Look for Chrome's translation bar (may appear automatically)"
echo "  3. Click 'Translate' button, OR right-click page and select 'Translate to English'"
echo "  4. Wait for translation to complete"