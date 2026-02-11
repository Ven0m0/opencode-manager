#!/bin/bash

set -e

echo "🔍 Checking prerequisites..."

# Check if bun is installed
if ! command -v bun &> /dev/null; then
  echo "❌ Bun is not installed. Please install it with:"
  echo "   curl -fsSL https://bun.sh/install | bash"
  exit 1
fi

echo "✅ Bun is installed"

# Check if Git is installed
if ! git --version &> /dev/null; then
  echo "❌ Git is not installed. Please install Git and try again."
  exit 1
fi

echo "✅ Git is installed"

# Check if OpenCode TUI is installed
if ! opencode --version &> /dev/null; then
  echo "❌ OpenCode TUI is not installed. Please install it with:"
  echo "   npm install -g @opencode/tui"
  echo "   or"
  echo "   bun add -g @opencode/tui"
  exit 1
fi

echo "✅ OpenCode TUI is installed"

# Create workspace directory if it doesn't exist
WORKSPACE_PATH="./workspace"
if [ ! -d "$WORKSPACE_PATH" ]; then
  echo "📁 Creating workspace directory at $WORKSPACE_PATH..."
  mkdir -p "$WORKSPACE_PATH/repos"
  mkdir -p "$WORKSPACE_PATH/config"
  echo "✅ Workspace directory created"
else
  echo "✅ Workspace directory exists"
fi

# Install dependencies using bun (handles workspaces)
echo "📦 Installing dependencies..."
bun install

echo "✅ Dependencies installed"

# Copy environment file if it doesn't exist
if [ ! -f ".env" ]; then
  echo "📝 Creating environment file..."
  cp .env.example .env
  echo "✅ Environment file created from .env.example"
else
  echo "✅ Environment file exists"
fi

echo "✅ Dev environment ready!"
echo ""
echo "🚀 To start development:"
echo "   bun dev              # Start both backend and frontend"
echo "   bun dev:backend      # Start backend only"
echo "   bun dev:frontend     # Start frontend only"
