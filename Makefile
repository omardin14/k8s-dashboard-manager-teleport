# Kubernetes Dashboard Manager with Teleport
# Makefile for easy project management

# Load configuration from config.yaml if available, otherwise use env vars
TELEPORT_PROXY_ADDR ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep proxy_addr | cut -d'"' -f2 | cut -d'"' -f1 || echo ""; fi)
TELEPORT_CLUSTER_NAME ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep cluster_name | cut -d'"' -f2 | cut -d'"' -f1 || echo ""; fi)
TELEPORT_CLUSTER_NAMESPACE ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep cluster_namespace | cut -d'"' -f2 | cut -d'"' -f1 || echo "teleport-cluster"; fi)
TELEPORT_AGENT_NAMESPACE ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep agent_namespace | cut -d'"' -f2 | cut -d'"' -f1 || echo "teleport-agent"; fi)
K8S_NAMESPACE ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^kubernetes:" config.yaml | grep namespace | cut -d'"' -f2 | cut -d'"' -f1 || echo "kubernetes-dashboard"; fi)

.PHONY: help config install setup-minikube check-minikube check-prerequisites start-minikube stop-minikube reset-minikube helm-deploy helm-clean helm-status get-tokens get-clusterip status logs debug-dashboard

# Default target
help:
	@echo "📊 Kubernetes Dashboard Manager with Teleport"
	@echo ""
	@echo "Available commands:"
	@echo "  make help              - Show this help message"
	@echo "  make config            - Create config.yaml from example"
	@echo "  make install           - Install Python dependencies"
	@echo ""
	@echo "Minikube Management:"
	@echo "  make setup-minikube    - Set up minikube cluster"
	@echo "  make check-minikube    - Check if minikube is installed"
	@echo "  make start-minikube    - Start minikube cluster"
	@echo "  make stop-minikube     - Stop minikube cluster"
	@echo "  make reset-minikube    - Reset minikube cluster"
	@echo ""
	@echo "Deployment:"
	@echo "  make helm-deploy       - Full automated deployment (RBAC + Teleport + Dashboard + Agent)"
	@echo "  make helm-clean        - Remove all deployed resources (complete cleanup)"
	@echo "  make helm-status       - Show deployment status"
	@echo ""
	@echo "Utilities:"
	@echo "  make get-tokens        - Get dashboard access tokens"
	@echo "  make get-clusterip     - Get dashboard ClusterIP"
	@echo "  make status            - Show overall status"
	@echo "  make logs              - Interactive menu to view logs (Teleport Server/Agent/Dashboard)"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. make config"
	@echo "  2. Edit config.yaml with your settings (optional - defaults work for local testing)"
	@echo "  3. make setup-minikube"
	@echo "  4. make helm-deploy (automatically installs dependencies and deploys everything!)"
	@echo ""
	@echo "That's it! The deployment will:"
	@echo "  - Deploy Teleport server to Kubernetes"
	@echo "  - Create admin user"
	@echo "  - Generate join token"
	@echo "  - Start port-forward to localhost:8080"
	@echo "  - Deploy Kubernetes Dashboard"
	@echo "  - Deploy Teleport agent"
	@echo ""
	@echo "To clean up everything: make helm-clean"

# Create config.yaml from example
config:
	@if [ ! -f config.yaml ]; then \
		cp config.yaml.example config.yaml; \
		echo "✅ Created config.yaml from example"; \
		echo "⚠️  Please edit config.yaml with your settings"; \
	else \
		echo "⚠️  config.yaml already exists"; \
	fi

# Install dependencies for local development
install:
	@echo "📦 Installing Python dependencies..."
	@echo "🔍 Setting up Python environment..."
	@if [ -d "venv" ]; then \
		echo "✅ Virtual environment found, activating..."; \
		. venv/bin/activate && cd src && pip install -r requirements.txt; \
	else \
		echo "🔧 Creating virtual environment..."; \
		python3 -m venv venv; \
		echo "✅ Virtual environment created, activating..."; \
		. venv/bin/activate && cd src && pip install -r requirements.txt; \
	fi
	@echo "✅ Dependencies installed!"
	@echo "💡 The Makefile will automatically use the virtual environment when running commands"

# Check if minikube is installed
check-minikube:
	@echo "🔍 Checking minikube installation..."
	@if command -v minikube >/dev/null 2>&1; then \
		echo "✅ Minikube is installed"; \
		minikube version; \
	else \
		echo "❌ Minikube is not installed"; \
		echo "Please install minikube: https://minikube.sigs.k8s.io/docs/start/"; \
		exit 1; \
	fi

# Set up minikube cluster
setup-minikube: check-minikube
	@echo "🚀 Setting up minikube cluster..."
	@minikube start || true
	@echo "📦 Enabling required minikube addons..."
	@minikube addons enable ingress 2>/dev/null || echo "⚠️  Ingress addon may already be enabled"
	@minikube addons enable ingress-dns 2>/dev/null || echo "⚠️  Ingress-DNS addon may already be enabled"
	@echo "✅ Minikube addons enabled"
	@echo "🔍 Checking /etc/hosts file for DNS mappings..."
	@if ! grep -q "teleport-cluster.teleport-cluster.svc.cluster.local" /etc/hosts 2>/dev/null; then \
		echo "⚠️  Missing DNS mapping in /etc/hosts"; \
		echo "   Please add the following to /etc/hosts (requires sudo):"; \
		echo "   127.0.0.1 teleport-cluster.teleport-cluster.svc.cluster.local"; \
		echo "   127.0.0.1 dashboard.teleport-cluster.teleport-cluster.svc.cluster.local"; \
	else \
		echo "✅ DNS mappings found in /etc/hosts"; \
	fi
	@echo "✅ Minikube cluster is ready"

# Start minikube
start-minikube: check-minikube
	@minikube start

# Stop minikube
stop-minikube:
	@minikube stop

# Reset minikube
reset-minikube: check-minikube
	@echo "🔄 Resetting minikube cluster..."
	@minikube delete || true
	@minikube start
	@echo "✅ Minikube cluster has been reset"

	@echo "🔐 Deploying RBAC resources..."
	@kubectl apply -f k8s/namespace.yaml
	@kubectl apply -f k8s/rbac.yaml
	@echo "⏳ Waiting for tokens to be generated..."
	@sleep 5
	@echo "✅ RBAC resources deployed!"

# Check prerequisites (minikube addons and /etc/hosts)
check-prerequisites:
	@sh -c "PROXY=\$$(grep -E '^\s*proxy_addr:' config.yaml 2>/dev/null | sed -E 's/.*proxy_addr:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/' | head -1 || echo ''); \
	if [ -z \"\$$PROXY\" ] || [ \"\$$PROXY\" = \"\" ]; then \
		echo '🔍 Checking prerequisites (Local Mode)...'; \
		echo '📦 Checking minikube installation...'; \
		if ! command -v minikube >/dev/null 2>&1; then \
			echo '❌ Minikube is not installed'; \
			echo '   Please install minikube: https://minikube.sigs.k8s.io/docs/start/'; \
			exit 1; \
		fi; \
		echo '✅ Minikube is installed'; \
		echo '🔍 Checking if minikube is running...'; \
		if ! minikube status >/dev/null 2>&1; then \
			echo '⚠️  Minikube is not running. Starting minikube...'; \
			minikube start || exit 1; \
			echo '✅ Minikube started'; \
		else \
			echo '✅ Minikube is running'; \
		fi; \
		echo '📦 Checking kubectl installation...'; \
		if ! command -v kubectl >/dev/null 2>&1; then \
			echo '❌ kubectl is not installed'; \
			echo '   Please install kubectl: https://kubernetes.io/docs/tasks/tools/'; \
			exit 1; \
		fi; \
		echo '✅ kubectl is installed'; \
		echo '🔍 Checking kubectl cluster connectivity...'; \
		if ! kubectl cluster-info >/dev/null 2>&1; then \
			echo '❌ kubectl cannot connect to a Kubernetes cluster'; \
			echo '   Please ensure minikube is running: make start-minikube'; \
			exit 1; \
		fi; \
		echo '✅ kubectl can connect to cluster'; \
		echo '📦 Checking minikube addons...'; \
		if minikube addons list 2>/dev/null | grep -q 'ingress.*enabled'; then \
			echo '✅ Ingress addon is enabled'; \
		else \
			echo '⚠️  Ingress addon is not enabled. Enabling now...'; \
			minikube addons enable ingress || exit 1; \
			echo '✅ Ingress addon enabled'; \
		fi; \
		if minikube addons list 2>/dev/null | grep -q 'ingress-dns.*enabled'; then \
			echo '✅ Ingress-DNS addon is enabled'; \
		else \
			echo '⚠️  Ingress-DNS addon is not enabled. Enabling now...'; \
			minikube addons enable ingress-dns || exit 1; \
			echo '✅ Ingress-DNS addon enabled'; \
		fi; \
		echo '🔍 Checking /etc/hosts DNS mappings...'; \
		if grep -q 'teleport-cluster.teleport-cluster.svc.cluster.local' /etc/hosts 2>/dev/null; then \
			echo '✅ Found teleport-cluster DNS mapping in /etc/hosts'; \
		else \
			echo '❌ Missing teleport-cluster DNS mapping in /etc/hosts'; \
			echo '   Add: 127.0.0.1 teleport-cluster.teleport-cluster.svc.cluster.local'; \
			exit 1; \
		fi; \
		if grep -q 'dashboard.teleport-cluster.teleport-cluster.svc.cluster.local' /etc/hosts 2>/dev/null; then \
			echo '✅ Found dashboard DNS mapping in /etc/hosts'; \
		else \
			echo '❌ Missing dashboard DNS mapping in /etc/hosts'; \
			echo '   Add: 127.0.0.1 dashboard.teleport-cluster.teleport-cluster.svc.cluster.local'; \
			exit 1; \
		fi; \
	else \
		echo '🔍 Checking prerequisites (Enterprise Mode)...'; \
		echo '📦 Checking minikube installation...'; \
		if command -v minikube >/dev/null 2>&1; then \
			echo '✅ Minikube is installed'; \
			echo '🔍 Checking if minikube is running...'; \
			if ! minikube status >/dev/null 2>&1; then \
				echo '⚠️  Minikube is not running. Starting minikube...'; \
				minikube start || exit 1; \
				echo '✅ Minikube started'; \
			else \
				echo '✅ Minikube is running'; \
			fi; \
		else \
			echo '⚠️  Minikube is not installed (optional for Enterprise Mode)'; \
		fi; \
		echo '📦 Checking kubectl installation...'; \
		if ! command -v kubectl >/dev/null 2>&1; then \
			echo '❌ kubectl is not installed'; \
			echo '   Please install kubectl: https://kubernetes.io/docs/tasks/tools/'; \
			exit 1; \
		fi; \
		echo '✅ kubectl is installed'; \
		echo '🔍 Checking kubectl cluster connectivity...'; \
		if ! kubectl cluster-info >/dev/null 2>&1; then \
			echo '❌ kubectl cannot connect to a Kubernetes cluster'; \
			echo '   Please configure kubectl to connect to your cluster:'; \
			echo '   - Set KUBECONFIG environment variable'; \
			echo '   - Or configure ~/.kube/config'; \
			echo '   - Or use: kubectl config set-cluster ...'; \
			exit 1; \
		fi; \
		echo '✅ kubectl can connect to cluster'; \
		CLUSTER_CTX=\$$(kubectl config current-context 2>/dev/null || echo 'unknown'); \
		echo \"✅ Current cluster context: \$$CLUSTER_CTX\"; \
	fi"

# Deploy using Helm (automated full deployment)
helm-deploy: check-prerequisites
	@if [ ! -d "venv" ]; then \
		echo "⚠️  Virtual environment not found. Running 'make install'..."; \
		$(MAKE) install; \
	fi
	@echo "✅ Using virtual environment..."; \
	. venv/bin/activate && python src/main.py deploy

# Clean up all deployments (Teleport server, Dashboard, Agent, port-forwards, RBAC)
helm-clean:
	@if [ ! -d "venv" ]; then \
		echo "⚠️  Virtual environment not found. Running 'make install'..."; \
		$(MAKE) install; \
	fi
	@echo "✅ Using virtual environment..."; \
	. venv/bin/activate && python src/main.py clean

# Show Helm deployment status
helm-status:
	@if [ ! -d "venv" ]; then \
		echo "⚠️  Virtual environment not found. Running 'make install'..."; \
		$(MAKE) install; \
	fi
	@. venv/bin/activate && python src/main.py helm-status

# Get dashboard access tokens
get-tokens:
	@if [ ! -d "venv" ]; then \
		echo "⚠️  Virtual environment not found. Running 'make install'..."; \
		$(MAKE) install; \
	fi
	@. venv/bin/activate && python src/main.py get-tokens

# Get dashboard ClusterIP
get-clusterip:
	@if [ ! -d "venv" ]; then \
		echo "⚠️  Virtual environment not found. Running 'make install'..."; \
		$(MAKE) install; \
	fi
	@. venv/bin/activate && python src/main.py get-clusterip

# Show overall status
status:
	@if [ ! -d "venv" ]; then \
		echo "⚠️  Virtual environment not found. Running 'make install'..."; \
		$(MAKE) install; \
	fi
	@. venv/bin/activate && python src/main.py status

# Show logs (interactive menu)
logs:
	@if [ ! -d "venv" ]; then \
		echo "⚠️  Virtual environment not found. Running 'make install'..."; \
		$(MAKE) install; \
	fi
	@. venv/bin/activate && python src/main.py logs

# Deploy Teleport server to Kubernetes using official Helm chart
# Port-forward Teleport web UI
# Stop Teleport port-forward
# Check Teleport server status
# View Teleport server logs
# Clean up Teleport server
# Create admin user in Teleport
# Delete admin user from Teleport
# Create readonly user in Teleport
# Delete readonly user from Teleport
# Generate Teleport join token

