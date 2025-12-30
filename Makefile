# Kubernetes Dashboard Manager with Teleport
# Makefile for easy project management

# Load configuration from config.yaml if available, otherwise use env vars
TELEPORT_PROXY_ADDR ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep proxy_addr | cut -d'"' -f2 | cut -d'"' -f1 || echo ""; fi)
TELEPORT_CLUSTER_NAME ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep cluster_name | cut -d'"' -f2 | cut -d'"' -f1 || echo ""; fi)
TELEPORT_JOIN_TOKEN ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep join_token | cut -d'"' -f2 | cut -d'"' -f1 || echo ""; fi)
TELEPORT_NAMESPACE ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep -A 1 "namespace:" | grep -v "^teleport:" | cut -d'"' -f2 | cut -d'"' -f1 || echo "teleport-agent"; fi)
K8S_NAMESPACE ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^kubernetes:" config.yaml | grep namespace | cut -d'"' -f2 | cut -d'"' -f1 || echo "kubernetes-dashboard"; fi)

.PHONY: help config setup-minikube check-minikube start-minikube stop-minikube reset-minikube helm-deploy helm-clean helm-status get-tokens get-clusterip status logs

# Default target
help:
	@echo "📊 Kubernetes Dashboard Manager with Teleport"
	@echo ""
	@echo "Available targets:"
	@echo "  setup-minikube - Install and setup minikube (if needed)"
	@echo "  start-minikube - Start minikube cluster"
	@echo "  stop-minikube  - Stop minikube cluster"
	@echo "  reset-minikube - Delete and recreate minikube cluster"
	@echo "  check-minikube - Check minikube status"
	@echo "  config         - Create config.yaml from example"
	@echo "  generate-token - Generate Teleport join token automatically (requires tctl)"
	@echo "  deploy-rbac    - Deploy RBAC resources (ServiceAccounts, Roles, Tokens)"
	@echo "  helm-deploy    - Deploy Dashboard and Teleport agent using Helm (recommended)"
	@echo "  helm-clean     - Clean up Helm release"
	@echo "  helm-status    - Check Helm release status"
	@echo "  get-tokens     - Get admin and readonly tokens"
	@echo "  get-clusterip   - Get Dashboard ClusterIP"
	@echo "  status         - Check deployment status"
	@echo "  logs           - View Teleport agent logs"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. make config  # Create config.yaml from example"
	@echo "  2. Edit config.yaml with teleport.proxy_addr and teleport.cluster_name"
	@echo "  3. make generate-token  # Auto-generate join token (or set manually)"
	@echo "  4. make setup-minikube"
	@echo "  5. make helm-deploy"
	@echo "  6. make get-tokens  # Get tokens for dashboard access"
	@echo ""
	@echo "Note: config.yaml contains all secrets and is NOT committed to git"

# Create config.yaml from example
config:
	@if [ -f config.yaml ]; then \
		echo "⚠️  config.yaml already exists. Backing up to config.yaml.bak"; \
		cp config.yaml config.yaml.bak; \
	fi
	@cp config.yaml.example config.yaml
	@echo "✅ Created config.yaml from example"
	@echo "📝 Please edit config.yaml with your Teleport proxy_addr and cluster_name"
	@echo "💡 Then run 'make generate-token' to auto-generate the join token"

# Generate Teleport join token
generate-token:
	@echo "🔑 Generating Teleport join token..."
	@if [ ! -f config.yaml ]; then \
		echo "❌ config.yaml not found. Run 'make config' first"; \
		exit 1; \
	fi
	@if ! command -v tctl >/dev/null 2>&1; then \
		echo "⚠️  tctl not found. Cannot auto-generate token."; \
		echo ""; \
		echo "Please generate token manually:"; \
		echo "  1. Via Teleport Web UI: Settings → Authentication → Tokens → Add Token"; \
		echo "     - Token Type: Kubernetes + Application"; \
		echo "     - Copy the generated token"; \
		echo "  2. Or install tctl and configure it: https://goteleport.com/docs/installation/"; \
		echo ""; \
		echo "Then update config.yaml with: teleport.join_token: \"YOUR_TOKEN\""; \
		exit 1; \
	fi
	@echo "📝 Checking tctl configuration..."
	@if ! tctl status >/dev/null 2>&1; then \
		echo "⚠️  tctl is not configured or cannot connect to Teleport cluster"; \
		echo ""; \
		echo "Please configure tctl:"; \
		echo "  1. Set TELEPORT environment variables, or"; \
		echo "  2. Configure ~/.tsh/config.yaml, or"; \
		echo "  3. Generate token manually via Teleport Web UI"; \
		echo ""; \
		echo "Then update config.yaml with: teleport.join_token: \"YOUR_TOKEN\""; \
		exit 1; \
	fi
	@echo "🔧 Generating join token with tctl..."
	@TOKEN_NAME="kube-dashboard-$$(date +%s)"; \
	TOKEN_OUTPUT=$$(tctl tokens add --type=kube,app --ttl=24h "$$TOKEN_NAME" 2>&1); \
	if [ $$? -eq 0 ]; then \
		TOKEN=$$(echo "$$TOKEN_OUTPUT" | grep -oE '[a-z0-9]{32}' | head -1); \
		if [ -z "$$TOKEN" ]; then \
			TOKEN=$$(echo "$$TOKEN_OUTPUT" | grep -i "token" | grep -oE '[a-z0-9]{32}' | head -1); \
		fi; \
		if [ -n "$$TOKEN" ]; then \
			echo "✅ Generated token: $$TOKEN"; \
			if [ "$$(uname)" = "Darwin" ]; then \
				sed -i '' "s/join_token:.*/join_token: \"$$TOKEN\"/" config.yaml; \
			else \
				sed -i "s/join_token:.*/join_token: \"$$TOKEN\"/" config.yaml; \
			fi; \
			echo "✅ Updated config.yaml with generated token"; \
			echo "⚠️  Token expires in 24 hours. For production, use longer TTL or rotate regularly."; \
		else \
			echo "⚠️  Could not extract token from tctl output"; \
			echo "Output: $$TOKEN_OUTPUT"; \
			echo ""; \
			echo "Please copy the token manually and update config.yaml"; \
			exit 1; \
		fi; \
	else \
		echo "❌ Failed to generate token: $$TOKEN_OUTPUT"; \
		echo ""; \
		echo "Please generate token manually:"; \
		echo "  1. Via Teleport Web UI: Settings → Authentication → Tokens"; \
		echo "  2. Or check tctl configuration"; \
		exit 1; \
	fi

# Check if minikube is installed
check-minikube:
	@echo "🔍 Checking minikube installation..."
	@if command -v minikube >/dev/null 2>&1; then \
		echo "✅ Minikube is installed"; \
		minikube version; \
	else \
		echo "❌ Minikube is not installed"; \
		echo "Run 'make setup-minikube' to install it"; \
		exit 1; \
	fi

# Install minikube
setup-minikube:
	@echo "🔧 Setting up minikube..."
	@if command -v minikube >/dev/null 2>&1; then \
		echo "✅ Minikube is already installed"; \
		minikube version; \
	else \
		echo "📦 Installing minikube..."; \
		if [ "$$(uname)" = "Darwin" ]; then \
			if command -v brew >/dev/null 2>&1; then \
				brew install minikube; \
			else \
				echo "❌ Homebrew not found"; \
				exit 1; \
			fi; \
		elif [ "$$(uname)" = "Linux" ]; then \
			curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64; \
			sudo install minikube-linux-amd64 /usr/local/bin/minikube; \
			rm minikube-linux-amd64; \
		fi; \
	fi
	@$(MAKE) start-minikube

# Start minikube cluster
start-minikube:
	@echo "🚀 Starting minikube cluster..."
	@if ! command -v minikube >/dev/null 2>&1; then \
		echo "❌ Minikube not found. Run 'make setup-minikube' first"; \
		exit 1; \
	fi
	@if minikube status 2>&1 | grep -q "host: Running"; then \
		echo "✅ Minikube is already running"; \
		echo "ℹ️  To restart, run 'make reset-minikube' first"; \
	else \
		minikube delete 2>/dev/null || true; \
		minikube start --driver=docker --cpus=2 --memory=3072; \
	fi
	@echo "✅ Minikube is running!"

# Stop minikube cluster
stop-minikube:
	@echo "🛑 Stopping minikube cluster..."
	@minikube stop
	@echo "✅ Minikube stopped!"

# Reset minikube cluster
reset-minikube:
	@echo "🔄 Resetting minikube cluster..."
	@minikube delete
	@$(MAKE) start-minikube

# Deploy RBAC resources
deploy-rbac:
	@echo "🔐 Deploying RBAC resources..."
	@kubectl apply -f k8s/namespace.yaml
	@kubectl apply -f k8s/rbac.yaml
	@echo "⏳ Waiting for tokens to be generated..."
	@sleep 5
	@echo "✅ RBAC resources deployed!"

# Deploy using Helm
helm-deploy: check-minikube deploy-rbac
	@echo "📊 Deploying Kubernetes Dashboard with Teleport..."
	@if [ -z "$(TELEPORT_JOIN_TOKEN)" ] || [ "$(TELEPORT_JOIN_TOKEN)" = "YOUR_TELEPORT_JOIN_TOKEN_HERE" ]; then \
		echo "❌ TELEPORT_JOIN_TOKEN not found in config.yaml"; \
		echo ""; \
		echo "Attempting to generate token automatically..."; \
		$(MAKE) generate-token || true; \
		TELEPORT_JOIN_TOKEN=$$(grep -A 1 "^teleport:" config.yaml | grep join_token | cut -d'"' -f2 2>/dev/null || echo ""); \
		if [ -z "$$TELEPORT_JOIN_TOKEN" ] || [ "$$TELEPORT_JOIN_TOKEN" = "YOUR_TELEPORT_JOIN_TOKEN_HERE" ]; then \
			echo ""; \
			echo "❌ Token generation failed or token not set"; \
			echo ""; \
			echo "Please set teleport.join_token manually:"; \
			echo "  1. Run 'make generate-token' (requires tctl configured)"; \
			echo "  2. Or manually edit config.yaml and set teleport.join_token"; \
			echo "  3. Or generate via Teleport Web UI: Settings → Authentication → Tokens"; \
			exit 1; \
		fi; \
		echo "✅ Using generated token"; \
	fi
	@if [ -z "$(TELEPORT_PROXY_ADDR)" ] || [ "$(TELEPORT_PROXY_ADDR)" = "your-proxy.teleport.com:443" ]; then \
		echo "❌ TELEPORT_PROXY_ADDR not found in config.yaml"; \
		echo "Please edit config.yaml and set teleport.proxy_addr"; \
		exit 1; \
	fi
	@if [ -z "$(TELEPORT_CLUSTER_NAME)" ] || [ "$(TELEPORT_CLUSTER_NAME)" = "your-k8s-cluster" ]; then \
		echo "❌ TELEPORT_CLUSTER_NAME not found in config.yaml"; \
		echo "Please edit config.yaml and set teleport.cluster_name"; \
		exit 1; \
	fi
	@echo "📦 Adding Helm repositories..."
	@helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard 2>/dev/null || true
	@helm repo add teleport https://charts.releases.teleport.dev 2>/dev/null || true
	@helm repo update
	@echo "🔧 Installing Kubernetes Dashboard..."
	@helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
		--create-namespace \
		--namespace $(K8S_NAMESPACE) \
		--wait --timeout=5m || true
	@echo "⏳ Waiting for Dashboard service to be ready..."
	@sleep 10
	@export CLUSTER_IP=$$(kubectl -n $(K8S_NAMESPACE) get svc kubernetes-dashboard -o jsonpath="{.spec.clusterIP}" 2>/dev/null || echo ""); \
	if [ -z "$$CLUSTER_IP" ]; then \
		echo "⚠️  Could not get ClusterIP, will use default"; \
		CLUSTER_IP="https://kubernetes-dashboard.$(K8S_NAMESPACE).svc.cluster.local"; \
	else \
		CLUSTER_IP="https://$$CLUSTER_IP"; \
	fi; \
	echo "📊 Dashboard URI: $$CLUSTER_IP"; \
	echo "🔧 Installing Teleport Kube Agent..."; \
	helm upgrade --install teleport-kube-agent teleport/teleport-kube-agent \
		--create-namespace \
		--namespace $(TELEPORT_NAMESPACE) \
		--set authToken=$(TELEPORT_JOIN_TOKEN) \
		--set joinParams.method=token \
		--set joinParams.tokenName=$(TELEPORT_JOIN_TOKEN) \
		--set proxyAddr=$(TELEPORT_PROXY_ADDR) \
		--set kubeClusterName=$(TELEPORT_CLUSTER_NAME) \
		--set roles=kube,app \
		--set labels.env=dev \
		--set labels.provider=kubernetes \
		--set apps[0].name=kube-dashboard-admin \
		--set apps[0].uri=$$CLUSTER_IP \
		--set apps[0].insecure_skip_verify=true \
		--set apps[0].labels.env=dev \
		--set apps[0].labels.role=admin \
		--set apps[1].name=kube-dashboard-readonly \
		--set apps[1].uri=$$CLUSTER_IP \
		--set apps[1].insecure_skip_verify=true \
		--set apps[1].labels.env=dev \
		--set apps[1].labels.role=readonly \
		--wait --timeout=5m
	@echo "✅ Deployment complete!"
	@echo ""
	@echo "📋 Next steps:"
	@echo "  1. Run 'make get-tokens' to get dashboard tokens"
	@echo "  2. Access dashboard via Teleport web UI"
	@echo "  3. Go to Applications → kube-dashboard-admin or kube-dashboard-readonly"

# Clean up Helm release
helm-clean:
	@echo "🧹 Cleaning up Helm releases..."
	@helm uninstall teleport-kube-agent --namespace $(TELEPORT_NAMESPACE) 2>/dev/null || true
	@helm uninstall kubernetes-dashboard --namespace $(K8S_NAMESPACE) 2>/dev/null || true
	@kubectl delete namespace $(TELEPORT_NAMESPACE) 2>/dev/null || true
	@echo "✅ Cleanup complete!"

# Check Helm release status
helm-status:
	@echo "📊 Helm Release Status:"
	@echo ""
	@echo "Kubernetes Dashboard:"
	@helm status kubernetes-dashboard --namespace $(K8S_NAMESPACE) 2>/dev/null || echo "  Not installed"
	@echo ""
	@echo "Teleport Kube Agent:"
	@helm status teleport-kube-agent --namespace $(TELEPORT_NAMESPACE) 2>/dev/null || echo "  Not installed"

# Get dashboard tokens
get-tokens:
	@echo "🔑 Dashboard Tokens:"
	@echo ""
	@echo "Admin Token:"
	@kubectl get secret dashboard-admin-token -n $(K8S_NAMESPACE) -o jsonpath="{.data.token}" 2>/dev/null | base64 -d || echo "  Secret not found"
	@echo ""
	@echo ""
	@echo "Readonly Token:"
	@kubectl get secret dashboard-readonly-token -n $(K8S_NAMESPACE) -o jsonpath="{.data.token}" 2>/dev/null | base64 -d || echo "  Secret not found"
	@echo ""

# Get Dashboard ClusterIP
get-clusterip:
	@echo "📊 Dashboard ClusterIP:"
	@kubectl -n $(K8S_NAMESPACE) get svc kubernetes-dashboard -o jsonpath="{.spec.clusterIP}" 2>/dev/null || echo "  Service not found"
	@echo ""

# Check deployment status
status:
	@echo "📊 Deployment Status:"
	@echo ""
	@echo "Namespaces:"
	@kubectl get namespaces | grep -E "$(K8S_NAMESPACE)|$(TELEPORT_NAMESPACE)" || echo "  No namespaces found"
	@echo ""
	@echo "Dashboard Pods:"
	@kubectl get pods -n $(K8S_NAMESPACE) || echo "  No pods found"
	@echo ""
	@echo "Teleport Agent Pods:"
	@kubectl get pods -n $(TELEPORT_NAMESPACE) || echo "  No pods found"
	@echo ""
	@echo "Services:"
	@kubectl get svc -n $(K8S_NAMESPACE) | grep kubernetes-dashboard || echo "  No services found"

# View logs
logs:
	@echo "📋 Teleport Agent Logs:"
	@kubectl logs -n $(TELEPORT_NAMESPACE) -l app=teleport-kube-agent --tail=50 || echo "  No logs found"

