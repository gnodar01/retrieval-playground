#!/bin/bash
# Retrieval Playground - Quick Start Script for Mac/Linux

set -e

echo ""
echo "🧩 Retrieval Playground - Podman Workshop Setup"
echo "================================================"
echo ""

# Prefer Podman Compose V2 plugin (`podman compose`); fall back to legacy `podman-compose`
if podman compose version &>/dev/null; then
    PODMAN_COMPOSE=(podman compose)
elif command -v podman-compose &>/dev/null; then
    PODMAN_COMPOSE=(podman-compose)
else
    echo "❌ Podman Compose is not installed!"
    echo ""
    echo "Linux:  sudo apt-get install podman-compose-plugin"
    echo "Mac:    brew install podman-compose"
    echo ""
    exit 1
fi

# Check if Podman is installed
if ! command -v podman &> /dev/null; then
    echo "❌ Podman is not installed!"
    echo ""
    echo "Please install Podman Desktop from:"
    echo "  https://docs.podman.com/desktop/install/mac-install/"
    echo ""
    exit 1
fi

# Check if Podman is running
if ! podman info &> /dev/null; then
    echo "❌ Podman is not running!"
    echo ""
    echo "Please start Podman Desktop and try again."
    echo ""
    exit 1
fi

echo "✅ Podman is installed and running"
echo ""

# Free space from failed/interrupted builds (common cause of "No space left on device")
if podman system df &>/dev/null; then
    echo "Podman disk usage:"
    podman system df
    echo ""
    DANGLING=$(podman images -f "dangling=true" -q 2>/dev/null | wc -l | tr -d ' ')
    if [ "$DANGLING" -gt 0 ]; then
      echo "Found $DANGLING dangling image layers from previous builds."
      read -rp "Clean them up? [y/N] " DO_DANGLING
        if [[ ! "$DO_DANGLING" =~ ^[Yy]$ ]]; then
            echo "Skipping dangling cleanup."
            echo ""
        else
            echo "Pruning dangling image layers..."
            echo ""
            podman image prune -f
        fi
    fi
fi

# Check for .env file
if [ ! -f .env ]; then
    echo "⚠️  .env file not found!"
    echo ""
    echo "Creating .env from template..."
    if [ -f .env.example ]; then
        cp .env.example .env
        echo "✅ .env file created"
        echo ""
        echo "⚠️  IMPORTANT: Edit the .env file and add your API keys!"
        echo "   Open .env in a text editor and replace the placeholder values."
        echo ""
        read -p "Press Enter after you've updated the .env file..."
    else
        echo "❌ .env.example not found. Creating basic template..."
        cat > .env << 'EOF'
GOOGLE_API_KEY=your_gemini_api_key
EOF
        echo "✅ .env file created"
        echo ""
        echo "⚠️  IMPORTANT: Edit the .env file and add your API keys!"
        echo ""
        exit 1
    fi
fi

BUILT=0
IMAGE_NAME="retrieval-playground-retrieval-playground:latest"
if podman image inspect "$IMAGE_NAME" &>/dev/null; then
    echo "Found existing workshop image ($IMAGE_NAME)."
    read -p "Rebuild image? [y/N] " REBUILD
    if [[ ! "$REBUILD" =~ ^[Yy]$ ]]; then
        echo "Skipping build, using existing image."
        echo ""
    else
        echo "Building Podman image (this may take 5-10 minutes)..."
        echo ""
        "${PODMAN_COMPOSE[@]}" build
        BUILT=1
    fi
else
    echo "Building Podman image (this may take 5-10 minutes on first run)..."
    echo "Tip: the image is ~11 GB (PyTorch, Docling, sentence-transformers)."
    echo "If the build fails with 'No space left on device', run:"
    echo "  podman system prune -a"
    echo "and ensure Podman has 20 GB+ free disk space."
    echo ""
    "${PODMAN_COMPOSE[@]}" build
    BUILT=1
fi

if [ "$BUILT" -eq 1 ]; then
    echo ""
    echo "✅ Build complete!"
fi

read -rp "Start image (compose up)? [y/N] " DO_START_IMAGE
if [[ ! "$DO_START_IMAGE" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Starting Jupyter Notebook server..."
    echo ""
    "${PODMAN_COMPOSE[@]}" up -d

    echo ""
    echo "✅ Jupyter Notebook is running!"
    echo ""
    echo "================================================"
    echo "📝 Access your notebooks at:"
    echo ""
    echo "   http://localhost:8888"
    echo ""
    echo "================================================"
    echo ""
    echo "📚 Navigate to: retrieval_playground/tutorial/"
    echo ""
    echo "💡 Useful commands:"
    echo "   Stop:     ${PODMAN_COMPOSE[*]} down"
    echo "   Restart:  ${PODMAN_COMPOSE[*]} restart"
    echo "   Logs:     ${PODMAN_COMPOSE[*]} logs -f"
    echo ""
fi
