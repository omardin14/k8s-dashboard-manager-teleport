# Kubernetes Dashboard Manager with Teleport
# Makefile for easy project management

# Load configuration from config.yaml if available, otherwise use env vars
TELEPORT_PROXY_ADDR ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep proxy_addr | cut -d'"' -f2 | cut -d'"' -f1 || echo ""; fi)
TELEPORT_CLUSTER_NAME ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep cluster_name | cut -d'"' -f2 | cut -d'"' -f1 || echo ""; fi)
TELEPORT_JOIN_TOKEN ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep join_token | cut -d'"' -f2 | cut -d'"' -f1 || echo ""; fi)
TELEPORT_NAMESPACE ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep -A 1 "namespace:" | grep -v "^teleport:" | cut -d'"' -f2 | cut -d'"' -f1 || echo "teleport-agent"; fi)
K8S_NAMESPACE ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^kubernetes:" config.yaml | grep namespace | cut -d'"' -f2 | cut -d'"' -f1 || echo "kubernetes-dashboard"; fi)

.PHONY: help config setup-minikube check-minikube start-minikube stop-minikube reset-minikube helm-deploy helm-clean helm-status get-tokens get-clusterip status logs setup-teleport-local setup-teleport-enterprise start-teleport stop-teleport teleport-status teleport-logs

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
	@echo "Teleport Setup (if not using existing Teleport):"
	@echo "  setup-teleport-local      - Setup Teleport Community Edition (local Docker for testing)"
	@echo "  start-teleport            - Start Teleport Community Edition (local Docker)"
	@echo "  stop-teleport             - Stop Teleport Docker container"
	@echo "  teleport-status           - Check Teleport container status"
	@echo "  teleport-logs             - View Teleport container logs (follow mode)"
	@echo "  teleport-debug            - Debug Teleport container (status, logs, certs)"
	@echo "  teleport-create-admin     - Create Teleport admin user (teleport-admin)"
	@echo "  teleport-delete-admin     - Delete Teleport admin user (teleport-admin)"
	@echo "  teleport-create-readonly  - Create Teleport readonly user (teleport-readonly)"
	@echo "  teleport-delete-readonly  - Delete Teleport readonly user (teleport-readonly)"
	@echo ""
	@echo "  Note: For Enterprise features, use Teleport Cloud (14-day trial):"
	@echo "        https://goteleport.com/signup/"
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
	@# Check if tctl is available (either on host or in container) and generate token
	@sh -c '\
	if command -v tctl >/dev/null 2>&1; then \
		echo "✅ Using tctl from host system..."; \
		TOKEN_OUTPUT=$$(tctl tokens add --type=kube,app --ttl=24h 2>&1); \
		TOKEN_EXIT=$$?; \
	elif docker ps --filter "name=teleport" --format "{{.Names}}" | grep -q teleport; then \
		echo "✅ Using tctl from Teleport container..."; \
		TOKEN_OUTPUT=$$(docker exec teleport tctl tokens add --type=kube,app --ttl=24h 2>&1); \
		TOKEN_EXIT=$$?; \
	elif docker ps --filter "name=teleport-enterprise" --format "{{.Names}}" | grep -q teleport-enterprise; then \
		echo "✅ Using tctl from Teleport Enterprise container..."; \
		TOKEN_OUTPUT=$$(docker exec teleport-enterprise tctl tokens add --type=kube,app --ttl=24h 2>&1); \
		TOKEN_EXIT=$$?; \
	else \
		echo "⚠️  tctl not found and Teleport container not running."; \
		echo ""; \
		echo "Please either:"; \
		echo "  1. Start Teleport: make start-teleport"; \
		echo "  2. Or install tctl on your host: https://goteleport.com/docs/installation/"; \
		echo "  3. Or generate token manually via Teleport Web UI"; \
		exit 1; \
	fi; \
	if [ $$TOKEN_EXIT -ne 0 ]; then \
		echo "❌ Failed to generate token:"; \
		echo "$$TOKEN_OUTPUT"; \
		echo ""; \
		echo "Please generate token manually:"; \
		echo "  1. Via Teleport Web UI: Settings → Authentication → Tokens → Add Token"; \
		echo "     - Token Type: Kubernetes + Application"; \
		echo "  2. Or run: docker exec teleport tctl tokens add --type=kube,app --ttl=24h"; \
		exit 1; \
	fi; \
	TOKEN=$$(echo "$$TOKEN_OUTPUT" | grep -oE "[a-z0-9]{32}" | head -1); \
	if [ -z "$$TOKEN" ]; then \
		TOKEN=$$(echo "$$TOKEN_OUTPUT" | grep -i "token" | grep -oE "[a-z0-9]{32}" | head -1); \
	fi; \
	if [ -z "$$TOKEN" ]; then \
		echo "⚠️  Could not extract token from output. Showing full output:"; \
		echo "$$TOKEN_OUTPUT"; \
		echo ""; \
		echo "Please manually extract the token (32 character string) and add to config.yaml"; \
		exit 1; \
	fi; \
	echo "✅ Generated token: $$TOKEN"; \
	if [ -f config.yaml ]; then \
		if [ "$(shell uname)" = "Darwin" ]; then \
			sed -i "" "s/join_token:.*/join_token: \"$$TOKEN\"/" config.yaml; \
		else \
			sed -i "s/join_token:.*/join_token: \"$$TOKEN\"/" config.yaml; \
		fi; \
		echo "✅ Updated config.yaml with join token"; \
		echo "⚠️  Token expires in 24 hours. For production, use longer TTL or rotate regularly."; \
	else \
		echo "⚠️  config.yaml not found. Token generated but not saved:"; \
		echo "   $$TOKEN"; \
		echo "   Please add to config.yaml: teleport.join_token: \"$$TOKEN\""; \
	fi'

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

# Setup Teleport Community Edition (local Docker - testing only)
setup-teleport-local:
	@echo "🚀 Setting up Teleport Community Edition (local Docker for testing)..."
	@chmod +x scripts/setup-teleport-local.sh
	@./scripts/setup-teleport-local.sh

# Detect docker compose command (docker compose or docker-compose)
DOCKER_COMPOSE := $(shell command -v docker-compose 2>/dev/null || echo "docker compose")

# Start Teleport (Community Edition - local Docker)
start-teleport:
	@echo "🚀 Starting Teleport Community Edition (local Docker)..."
	@$(DOCKER_COMPOSE) -f docker-compose.teleport.yml up -d
	@echo "⏳ Waiting for Teleport to be ready (this may take 1-2 minutes for first-time installation)..."
	@echo "   Installing Teleport (~194 MB download) and starting services..."
	@sleep 30
	@echo "📋 Checking Teleport status..."
	@docker logs teleport --tail=20 2>/dev/null | grep -E "(✅|🚀|ERROR|error|Teleport|started)" || echo "   Still installing/starting..."
	@echo ""
	@echo "✅ Container started! Teleport may still be installing/starting."
	@echo "   Check logs with: make teleport-logs"
	@echo "   Wait a bit longer if you see installation progress in logs."
	@echo "📊 Access Teleport Web UI at: https://localhost:3080"
	@echo ""
	@echo "📋 Next steps:"
	@echo "  1. Access https://localhost:3080 and accept terms"
	@echo "  2. Create a user: docker exec -it teleport tctl users add teleport-admin --roles=editor,access"
	@echo "  3. Update config.yaml with:"
	@echo "     teleport.proxy_addr: \"localhost:3080\""
	@echo "     teleport.cluster_name: \"localhost\""

# Stop Teleport
stop-teleport:
	@echo "🛑 Stopping Teleport..."
	@$(DOCKER_COMPOSE) -f docker-compose.teleport.yml down 2>/dev/null || true
	@echo "✅ Teleport stopped!"

# Clean Teleport config (if corrupted)
clean-teleport-config:
	@echo "🧹 Cleaning Teleport config..."
	@rm -f teleport-config/teleport.yaml
	@echo "✅ Config cleaned. Restart with: make start-teleport"

# Check Teleport status
teleport-status:
	@echo "📊 Teleport Container Status:"
	@docker ps --filter "name=teleport" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "  Teleport not running"

# View Teleport logs (follow mode - press Ctrl-C to exit)
teleport-logs:
	@echo "📋 Teleport Container Logs (following - press Ctrl-C to exit):"
	@echo ""
	@docker logs -f teleport 2>/dev/null || docker logs -f teleport-enterprise 2>/dev/null || echo "  Teleport container not found"

# Create Teleport admin user
teleport-create-admin:
	@echo "👤 Creating Teleport admin user..."
	@echo ""
	@OUTPUT=$$(docker exec teleport tctl users add teleport-admin --roles=editor,access --logins=root,ubuntu,ec2-user 2>&1 || docker exec teleport-enterprise tctl users add teleport-admin --roles=editor,access --logins=root,ubuntu,ec2-user 2>&1); \
	if [ $$? -eq 0 ]; then \
		echo "$$OUTPUT" | sed 's|https://localhost:443|https://localhost:3080|g'; \
		echo ""; \
		echo "✅ User created! Use the URL above (with port 3080) to complete setup."; \
	else \
		echo "$$OUTPUT"; \
		echo "❌ Failed to create user. Is Teleport container running?"; \
	fi

# Delete Teleport admin user
teleport-delete-admin:
	@echo "🗑️  Deleting Teleport admin user..."
	@echo ""
	@docker exec teleport tctl users rm teleport-admin 2>&1 || docker exec teleport-enterprise tctl users rm teleport-admin 2>&1 || \
		(echo "⚠️  User may not exist or container not running. Continuing..." && exit 0)
	@echo "✅ User deleted (if it existed)"

# Create Teleport readonly user
teleport-create-readonly:
	@echo "👤 Creating Teleport readonly user..."
	@echo ""
	@OUTPUT=$$(docker exec teleport tctl users add teleport-readonly --roles=access --logins=root,ubuntu,ec2-user 2>&1 || docker exec teleport-enterprise tctl users add teleport-readonly --roles=access --logins=root,ubuntu,ec2-user 2>&1); \
	if [ $$? -eq 0 ]; then \
		echo "$$OUTPUT" | sed 's|https://localhost:443|https://localhost:3080|g'; \
		echo ""; \
		echo "✅ Readonly user created! Use the URL above (with port 3080) to complete setup."; \
		echo "   Note: This user has 'access' role only (read-only permissions)."; \
	else \
		echo "$$OUTPUT"; \
		echo "❌ Failed to create user. Is Teleport container running?"; \
	fi

# Delete Teleport readonly user
teleport-delete-readonly:
	@echo "🗑️  Deleting Teleport readonly user..."
	@echo ""
	@docker exec teleport tctl users rm teleport-readonly 2>&1 || docker exec teleport-enterprise tctl users rm teleport-readonly 2>&1 || \
		(echo "⚠️  User may not exist or container not running. Continuing..." && exit 0)
	@echo "✅ User deleted (if it existed)"

# Debug Teleport container
teleport-debug:
	@echo "🔍 Teleport Container Debug Info:"
	@echo ""
	@echo "Container Status:"
	@docker ps -a --filter "name=teleport" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  Cannot access Docker"
	@echo ""
	@echo "Recent Logs:"
	@docker logs teleport --tail=50 2>/dev/null || docker logs teleport-enterprise --tail=50 2>/dev/null || echo "  No logs available"
	@echo ""
	@echo "Certificate Check:"
	@ls -la teleport-tls/ 2>/dev/null || echo "  teleport-tls directory not found"
	@echo ""
	@echo "Config Check:"
	@ls -la teleport-config/ 2>/dev/null || echo "  teleport-config directory not found"

