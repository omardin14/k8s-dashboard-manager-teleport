#!/bin/bash
# Setup script for Teleport Community Edition (local Docker deployment)
# Based on: https://goteleport.com/docs/get-started/deploy-community/

set -e

echo "🚀 Setting up Teleport Community Edition (Local Docker)"

# Check if Docker is installed
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if mkcert is installed (for local certificates)
if ! command -v mkcert >/dev/null 2>&1; then
    echo "⚠️  mkcert not found. Installing mkcert..."
    if [ "$(uname)" = "Darwin" ]; then
        if command -v brew >/dev/null 2>&1; then
            brew install mkcert
        else
            echo "❌ Homebrew not found. Please install mkcert manually: https://github.com/FiloSottile/mkcert"
            exit 1
        fi
    elif [ "$(uname)" = "Linux" ]; then
        echo "Please install mkcert manually: https://github.com/FiloSottile/mkcert"
        exit 1
    fi
fi

# Create directories
echo "📁 Creating directories..."
mkdir -p teleport-data
mkdir -p teleport-config
mkdir -p teleport-tls

# Setup mkcert
echo "🔐 Setting up local certificate authority..."
if [ ! -f "$(mkcert -CAROOT)/rootCA.pem" ]; then
    mkcert -install
fi

# Generate certificates
echo "📜 Generating TLS certificates..."
cd teleport-tls
if [ ! -f localhost.pem ]; then
    mkcert localhost
    echo "✅ Generated localhost.pem and localhost-key.pem"
fi

# Copy CA certificate
cp "$(mkcert -CAROOT)/rootCA.pem" rootCA.pem
cd ..

# Copy certificates to teleport-config (if they exist)
if [ -f teleport-tls/localhost.pem ]; then
    cp teleport-tls/localhost.pem teleport-config/
    cp teleport-tls/localhost-key.pem teleport-config/
    echo "✅ Copied certificates to teleport-config/"
else
    echo "⚠️  Certificates not found. They will be generated on first Teleport start."
fi

echo "✅ Teleport setup complete!"
echo ""
echo "📋 Next steps:"
echo "  1. Start Teleport: make start-teleport"
echo "     (or manually: docker compose -f docker-compose.teleport.yml up -d)"
echo "  2. Access Teleport Web UI: https://localhost:3080"
echo "  3. Create a user: docker exec -it teleport tctl users add teleport-admin --roles=editor,access"
echo "  4. Update config.yaml with:"
echo "     teleport.proxy_addr: \"localhost:3080\""
echo "     teleport.cluster_name: \"localhost\""

