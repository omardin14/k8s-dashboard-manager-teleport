# Kubernetes Dashboard Manager with Teleport
# Makefile for easy project management

# Load configuration from config.yaml if available, otherwise use env vars
TELEPORT_PROXY_ADDR ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep proxy_addr | cut -d'"' -f2 | cut -d'"' -f1 || echo ""; fi)
TELEPORT_CLUSTER_NAME ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep cluster_name | cut -d'"' -f2 | cut -d'"' -f1 || echo ""; fi)
TELEPORT_JOIN_TOKEN ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep join_token | cut -d'"' -f2 | cut -d'"' -f1 || echo ""; fi)
TELEPORT_NAMESPACE ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep -A 1 "namespace:" | grep -v "^teleport:" | cut -d'"' -f2 | cut -d'"' -f1 || echo "teleport-cluster"; fi)
K8S_NAMESPACE ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^kubernetes:" config.yaml | grep namespace | cut -d'"' -f2 | cut -d'"' -f1 || echo "kubernetes-dashboard"; fi)

.PHONY: help config setup-minikube check-minikube start-minikube stop-minikube reset-minikube helm-deploy helm-clean helm-status get-tokens get-clusterip status logs dashboard-logs teleport-agent-logs deploy-teleport teleport-port-forward teleport-stop-port-forward teleport-status teleport-logs teleport-clean teleport-create-admin teleport-delete-admin teleport-create-readonly teleport-delete-readonly generate-token deploy-kube-agent clean-kube-agent deploy-kube-agent

# Default target
help:
	@echo "📊 Kubernetes Dashboard Manager with Teleport"
	@echo ""
	@echo "Available commands:"
	@echo "  make help              - Show this help message"
	@echo "  make config            - Create config.yaml from example"
	@echo ""
	@echo "Minikube Management:"
	@echo "  make setup-minikube    - Set up minikube cluster"
	@echo "  make check-minikube    - Check if minikube is installed"
	@echo "  make start-minikube    - Start minikube cluster"
	@echo "  make stop-minikube     - Stop minikube cluster"
	@echo "  make reset-minikube    - Reset minikube cluster"
	@echo ""
	@echo "Deployment:"
	@echo "  make helm-deploy       - Full automated deployment (Teleport + Dashboard + Agent)"
	@echo "  make deploy-kube-agent - Deploy only the Teleport Kube Agent (requires Teleport server)"
	@echo "  make clean-kube-agent  - Clean up only Teleport Kube Agent resources"
	@echo "  make helm-clean        - Remove all deployed resources (complete cleanup)"
	@echo "  make helm-status       - Show deployment status"
	@echo ""
	@echo "Teleport Management:"
	@echo "  make deploy-teleport        - Deploy Teleport server to Kubernetes"
	@echo "  make teleport-port-forward  - Port-forward Teleport web UI (Ctrl-C to exit)"
	@echo "  make teleport-status        - Check Teleport server status"
	@echo "  make teleport-logs          - View Teleport server logs (Ctrl-C to exit)"
	@echo "  make teleport-create-admin  - Create admin user in Teleport"
	@echo "  make teleport-delete-admin  - Delete admin user from Teleport"
	@echo "  make teleport-create-readonly - Create readonly user in Teleport"
	@echo "  make teleport-delete-readonly - Delete readonly user from Teleport"
	@echo "  make generate-token         - Generate Teleport join token"
	@echo "  make teleport-clean         - Remove Teleport server from Kubernetes"
	@echo ""
	@echo "Utilities:"
	@echo "  make get-tokens        - Get dashboard access tokens"
	@echo "  make get-clusterip     - Get dashboard ClusterIP"
	@echo "  make status            - Show overall status"
	@echo "  make dashboard-logs    - Follow Kubernetes Dashboard logs (real-time, Ctrl-C to exit)"
	@echo "  make teleport-agent-logs - Follow Teleport Kube Agent logs (real-time, Ctrl-C to exit)"
	@echo "  make logs              - Interactive menu to view logs (Teleport Server/Agent/Dashboard)"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. make config"
	@echo "  2. Edit config.yaml with your settings (optional - defaults work for local testing)"
	@echo "  3. make setup-minikube"
	@echo "  4. make helm-deploy (does everything automatically!)"
	@echo ""
	@echo "That's it! The deployment will:"
	@echo "  - Deploy Teleport server to Kubernetes"
	@echo "  - Create admin user"
	@echo "  - Generate join token"
	@echo "  - Start port-forward to localhost:3080"
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

# Deploy RBAC resources
deploy-rbac:
	@echo "🔐 Deploying RBAC resources..."
	@kubectl apply -f k8s/namespace.yaml
	@kubectl apply -f k8s/rbac.yaml
	@echo "⏳ Waiting for tokens to be generated..."
	@sleep 5
	@echo "✅ RBAC resources deployed!"

# Deploy using Helm (automated full deployment)
helm-deploy: check-minikube deploy-rbac
	@echo "🚀 Starting full deployment (Teleport + Dashboard + Agent)..."
	@echo ""
	@echo "Step 1/5: Deploying Teleport server to Kubernetes..."
	@$(MAKE) deploy-teleport
	@echo ""
	@echo "Step 2/5: Setting up Teleport admin user..."
	@POD=$$(kubectl -n teleport-cluster get pods -l app.kubernetes.io/name=teleport-cluster,app.kubernetes.io/component=auth -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""); \
	if [ -n "$$POD" ]; then \
		NS="teleport-cluster"; \
	elif [ -n "$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")" ]; then \
		POD=$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}'); \
		NS="teleport"; \
	else \
		echo "❌ Teleport server pod not found"; \
		exit 1; \
	fi; \
	if [ -z "$$POD" ]; then \
		echo "❌ Teleport server pod not found"; \
		exit 1; \
	fi; \
	USER_EXISTS=$$(kubectl exec -n $$NS $$POD -- tctl users ls 2>/dev/null | grep -q "admin" && echo "yes" || echo "no"); \
	if [ "$$USER_EXISTS" = "no" ]; then \
		echo "👤 Creating admin user..."; \
		OUTPUT=$$(kubectl exec -n $$NS $$POD -- tctl users add admin --roles=editor,access --logins=root,admin 2>&1 || \
		kubectl exec -n $$NS $$POD -- tctl users add admin --roles=editor,access --logins root,admin 2>&1 || echo ""); \
		if [ -n "$$OUTPUT" ]; then \
			INVITE_URL=$$(echo "$$OUTPUT" | grep -oE 'https://[^[:space:]]+/web/invite/[^[:space:]]+' | head -1); \
			if [ -n "$$INVITE_URL" ]; then \
				INVITE_URL=$$(echo "$$INVITE_URL" | sed 's|https://teleport-cluster\.teleport-cluster\.svc\.cluster\.local:443|https://localhost:3080|g' | sed 's|https://teleport\.local:443|https://localhost:3080|g' | sed 's|teleport\.local:443|localhost:3080|g'); \
				echo "$$OUTPUT" | sed 's|https://teleport-cluster\.teleport-cluster\.svc\.cluster\.local:443|https://localhost:3080|g' | sed 's|https://teleport\.local:443|https://localhost:3080|g' | sed 's|teleport\.local:443|localhost:3080|g'; \
				echo "$$INVITE_URL" > /tmp/teleport-admin-invite-url.txt; \
			else \
				echo "$$OUTPUT" | sed 's|https://teleport-cluster\.teleport-cluster\.svc\.cluster\.local:443|https://localhost:3080|g' | sed 's|https://teleport\.local:443|https://localhost:3080|g' | sed 's|teleport\.local:443|localhost:3080|g'; \
			fi; \
		fi; \
		echo "✅ Admin user created"; \
	else \
		echo "👤 Admin user already exists, resetting to get new invite URL..."; \
		OUTPUT=$$(kubectl exec -n $$NS $$POD -- tctl users reset admin 2>&1 || echo ""); \
		if [ -n "$$OUTPUT" ]; then \
			INVITE_URL=$$(echo "$$OUTPUT" | grep -oE 'https://[^[:space:]]+/web/invite/[^[:space:]]+' | head -1); \
			if [ -n "$$INVITE_URL" ]; then \
				INVITE_URL=$$(echo "$$INVITE_URL" | sed 's|https://teleport-cluster\.teleport-cluster\.svc\.cluster\.local:443|https://localhost:3080|g' | sed 's|https://teleport\.local:443|https://localhost:3080|g' | sed 's|teleport\.local:443|localhost:3080|g'); \
				echo "$$OUTPUT" | sed 's|https://teleport-cluster\.teleport-cluster\.svc\.cluster\.local:443|https://localhost:3080|g' | sed 's|https://teleport\.local:443|https://localhost:3080|g' | sed 's|teleport\.local:443|localhost:3080|g'; \
				echo "$$INVITE_URL" > /tmp/teleport-admin-invite-url.txt; \
			else \
				echo "$$OUTPUT" | sed 's|https://teleport-cluster\.teleport-cluster\.svc\.cluster\.local:443|https://localhost:3080|g' | sed 's|https://teleport\.local:443|https://localhost:3080|g' | sed 's|teleport\.local:443|localhost:3080|g'; \
			fi; \
		fi; \
		echo "✅ Admin user reset"; \
	fi
	@echo ""
	@echo "Step 3/5: Generating Teleport join token..."
	@POD=$$(kubectl -n teleport-cluster get pods -l app.kubernetes.io/name=teleport-cluster,app.kubernetes.io/component=auth -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""); \
	if [ -n "$$POD" ]; then \
		NS="teleport-cluster"; \
	elif [ -n "$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")" ]; then \
		POD=$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}'); \
		NS="teleport"; \
	else \
		echo "❌ Teleport server pod not found"; \
		exit 1; \
	fi; \
	if [ -z "$$POD" ]; then \
		echo "❌ Teleport server pod not found"; \
		exit 1; \
	fi; \
	TOKEN_OUTPUT=$$(kubectl exec -n $$NS $$POD -- tctl tokens add --type=kube,app --ttl=24h 2>&1); \
	TOKEN_EXIT=$$?; \
	if [ $$TOKEN_EXIT -eq 0 ]; then \
		TOKEN=$$(echo "$$TOKEN_OUTPUT" | grep -oE '[a-f0-9]{32}' | head -1); \
		if [ -n "$$TOKEN" ]; then \
			echo "✅ Generated token: $$TOKEN"; \
			if [ -f config.yaml ]; then \
				sed -i.bak "s/join_token:.*/join_token: \"$$TOKEN\"/" config.yaml && rm -f config.yaml.bak 2>/dev/null || \
				sed -i '' "s/join_token:.*/join_token: \"$$TOKEN\"/" config.yaml 2>/dev/null || true; \
				echo "✅ Updated config.yaml with join token"; \
			fi; \
		else \
			echo "⚠️  Failed to extract token from output, checking existing token..."; \
			TOKEN=$$(grep -E '^\s*join_token:' config.yaml 2>/dev/null | sed -E 's/.*join_token:[[:space:]]*["'\'']?([^"'\'']+)["'\'']?.*/\1/' | head -1); \
			if [ -z "$$TOKEN" ] || [ "$$TOKEN" = "YOUR_TELEPORT_JOIN_TOKEN_HERE" ]; then \
				echo "❌ Token not found. Please check Teleport server logs"; \
				exit 1; \
			fi; \
		fi; \
	else \
		echo "⚠️  Token generation failed, checking existing token..."; \
		TOKEN=$$(grep -E '^\s*join_token:' config.yaml 2>/dev/null | sed -E 's/.*join_token:[[:space:]]*["'\'']?([^"'\'']+)["'\'']?.*/\1/' | head -1); \
		if [ -z "$$TOKEN" ] || [ "$$TOKEN" = "YOUR_TELEPORT_JOIN_TOKEN_HERE" ]; then \
			echo "❌ Token not found. Please check Teleport server logs or run 'make generate-token' manually"; \
			exit 1; \
		fi; \
		echo "✅ Using existing token from config.yaml"; \
	fi
	@echo ""
	@echo "Step 4/5: Starting Teleport port-forward in background..."
	@if pgrep -f "kubectl port-forward.*teleport.*3080" > /dev/null; then \
		echo "✅ Port-forward already running"; \
	else \
		if kubectl get svc teleport-cluster -n teleport-cluster >/dev/null 2>&1; then \
			kubectl port-forward -n teleport-cluster svc/teleport-cluster 3080:443 > /tmp/teleport-port-forward.log 2>&1 & \
			echo $$! > /tmp/teleport-port-forward.pid; \
		elif kubectl get svc teleport -n teleport >/dev/null 2>&1; then \
			kubectl port-forward -n teleport svc/teleport 3080:3080 > /tmp/teleport-port-forward.log 2>&1 & \
			echo $$! > /tmp/teleport-port-forward.pid; \
		else \
			echo "⚠️  Teleport service not found. Port-forward will need to be started manually."; \
		fi; \
		sleep 2; \
		if pgrep -f "kubectl port-forward.*teleport.*3080" > /dev/null; then \
			echo "✅ Port-forward started (PID: $$(cat /tmp/teleport-port-forward.pid))"; \
			echo "   Access Teleport at: https://localhost:3080"; \
		else \
			echo "⚠️  Port-forward failed to start. You may need to run 'make teleport-port-forward' manually"; \
		fi; \
	fi
	@echo ""
	@echo "Step 5/5: Deploying Dashboard and Teleport Agent..."
	@sh -c "set -e; \
	TOKEN=\$$(grep -E '^\s*join_token:' config.yaml 2>/dev/null | sed -E 's/.*join_token:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/' | head -1); \
	if [ -z \"\$$TOKEN\" ] || [ \"\$$TOKEN\" = \"YOUR_TELEPORT_JOIN_TOKEN_HERE\" ]; then \
		echo '❌ Token not found in config.yaml'; \
		exit 1; \
	fi; \
	PROXY=\$$(grep -E '^\s*proxy_addr:' config.yaml 2>/dev/null | sed -E 's/.*proxy_addr:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/' | head -1); \
	if [ -z \"\$$PROXY\" ] || [ \"\$$PROXY\" = \"your-proxy.teleport.com:443\" ]; then \
		if [ -n \"$(TELEPORT_PROXY_ADDR)\" ] && [ \"$(TELEPORT_PROXY_ADDR)\" != \"your-proxy.teleport.com:443\" ]; then \
			PROXY=\"$(TELEPORT_PROXY_ADDR)\"; \
		else \
			echo '❌ TELEPORT_PROXY_ADDR not found in config.yaml'; \
			exit 1; \
		fi; \
	fi; \
	if echo \"\$$PROXY\" | grep -q \"localhost\" || [ -z \"\$$PROXY\" ] || [ \"\$$PROXY\" = \"your-proxy.teleport.com:443\" ]; then \
		echo '⚠️  Using Kubernetes service address for Teleport...'; \
		if kubectl get svc teleport-cluster -n teleport-cluster >/dev/null 2>&1; then \
			PROXY=\"teleport-cluster.teleport-cluster.svc.cluster.local:443\"; \
		else \
			PROXY=\"teleport.teleport.svc.cluster.local:3080\"; \
		fi; \
		echo \"✅ Using Kubernetes service: \$$PROXY\"; \
	fi; \
	CLUSTER=\$$(grep -E '^\s*cluster_name:' config.yaml 2>/dev/null | sed -E 's/.*cluster_name:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/' | head -1); \
	if [ -z \"\$$CLUSTER\" ] || [ \"\$$CLUSTER\" = \"your-k8s-cluster\" ]; then \
		if [ -n \"$(TELEPORT_CLUSTER_NAME)\" ] && [ \"$(TELEPORT_CLUSTER_NAME)\" != \"your-k8s-cluster\" ]; then \
			CLUSTER=\"$(TELEPORT_CLUSTER_NAME)\"; \
		else \
			echo '❌ TELEPORT_CLUSTER_NAME not found in config.yaml'; \
			exit 1; \
		fi; \
	fi; \
	K8S_NS=\$$(grep -A 2 '^kubernetes:' config.yaml 2>/dev/null | grep -E '^\s*namespace:' | sed -E 's/.*namespace:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/' | head -1); \
	if [ -z \"\$$K8S_NS\" ]; then \
		K8S_NS=\"kubernetes-dashboard\"; \
	fi; \
	TELEPORT_NS=\$$(grep -A 2 '^teleport:' config.yaml 2>/dev/null | grep -E '^\s*namespace:' | sed -E 's/.*namespace:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/' | head -1); \
	if [ -z \"\$$TELEPORT_NS\" ]; then \
		TELEPORT_NS=\"teleport-cluster\"; \
	fi; \
	echo \"✅ Using token: \$$TOKEN\"; \
	echo \"✅ Using proxy: \$$PROXY\"; \
	echo \"✅ Using cluster: \$$CLUSTER\"; \
	echo \"✅ Using K8S namespace: \$$K8S_NS\"; \
	echo \"✅ Using Teleport namespace: \$$TELEPORT_NS\"; \
	echo '📦 Adding Helm repositories...'; \
	helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard 2>/dev/null || true; \
	helm repo add teleport https://charts.releases.teleport.dev 2>/dev/null || true; \
	helm repo update; \
	echo '🔧 Installing Kubernetes Dashboard...'; \
	helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
		--create-namespace \
		--namespace \$$K8S_NS \
		--wait --timeout=5m || true; \
	echo '⏳ Waiting for Dashboard service to be ready...'; \
	sleep 10; \
	CLUSTER_IP=\$$(kubectl -n \$$K8S_NS get svc kubernetes-dashboard -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo ''); \
	if [ -z \"\$$CLUSTER_IP\" ]; then \
		echo '⚠️  Could not get ClusterIP, will use default'; \
		CLUSTER_IP=\"https://kubernetes-dashboard.\$$K8S_NS.svc.cluster.local\"; \
	else \
		CLUSTER_IP=\"https://\$$CLUSTER_IP\"; \
	fi; \
	echo \"📊 Dashboard URI: \$$CLUSTER_IP\"; \
	echo '🔧 Installing Teleport Kube Agent...'; \
	TEMP_VALUES=\$$(mktemp); \
	echo \"authToken: \$$TOKEN\" > \$$TEMP_VALUES; \
	echo 'joinParams:' >> \$$TEMP_VALUES; \
	echo '  method: token' >> \$$TEMP_VALUES; \
	echo \"  tokenName: \$$TOKEN\" >> \$$TEMP_VALUES; \
	echo \"proxyAddr: \$$PROXY\" >> \$$TEMP_VALUES; \
	echo \"kubeClusterName: \$$CLUSTER\" >> \$$TEMP_VALUES; \
	echo 'insecureSkipProxyTLSVerify: true' >> \$$TEMP_VALUES; \
	echo 'labels:' >> \$$TEMP_VALUES; \
	echo '  env: dev' >> \$$TEMP_VALUES; \
	echo '  provider: kubernetes' >> \$$TEMP_VALUES; \
	echo 'roles: kube,app' >> \$$TEMP_VALUES; \
	echo 'apps:' >> \$$TEMP_VALUES; \
	echo '- name: kube-dashboard' >> \$$TEMP_VALUES; \
	echo \"  uri: \$$CLUSTER_IP\" >> \$$TEMP_VALUES; \
	echo '  insecure_skip_verify: true' >> \$$TEMP_VALUES; \
	echo '  labels:' >> \$$TEMP_VALUES; \
	echo '    env: dev' >> \$$TEMP_VALUES; \
	helm upgrade --install teleport-kube-agent teleport/teleport-kube-agent \
		--create-namespace \
		--namespace \$$TELEPORT_NS \
		-f \$$TEMP_VALUES \
		--wait --timeout=5m || true; \
	rm -f \$$TEMP_VALUES"
	@echo ""
	@echo "✅ Full deployment complete!"
	@echo ""

# Deploy only the Teleport Kube Agent (without Dashboard or Teleport server setup)
deploy-kube-agent:
	@echo "🔧 Deploying Teleport Kube Agent..."
	@sh -c "set -e; \
	TOKEN=\$$(grep -E '^\s*join_token:' config.yaml 2>/dev/null | sed -E 's/.*join_token:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/' | head -1); \
	if [ -z \"\$$TOKEN\" ] || [ \"\$$TOKEN\" = \"YOUR_TELEPORT_JOIN_TOKEN_HERE\" ]; then \
		echo '❌ Token not found in config.yaml. Run: make generate-token'; \
		exit 1; \
	fi; \
	PROXY=\$$(grep -E '^\s*proxy_addr:' config.yaml 2>/dev/null | sed -E 's/.*proxy_addr:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/' | head -1); \
	if [ -z \"\$$PROXY\" ] || [ \"\$$PROXY\" = \"your-proxy.teleport.com:443\" ]; then \
		if [ -n \"$(TELEPORT_PROXY_ADDR)\" ] && [ \"$(TELEPORT_PROXY_ADDR)\" != \"your-proxy.teleport.com:443\" ]; then \
			PROXY=\"$(TELEPORT_PROXY_ADDR)\"; \
		else \
			echo '❌ TELEPORT_PROXY_ADDR not found in config.yaml'; \
			exit 1; \
		fi; \
	fi; \
	if echo \"\$$PROXY\" | grep -q \"localhost\" || [ -z \"\$$PROXY\" ] || [ \"\$$PROXY\" = \"your-proxy.teleport.com:443\" ]; then \
		echo '⚠️  Using Kubernetes service address for Teleport...'; \
		if kubectl get svc teleport-cluster -n teleport-cluster >/dev/null 2>&1; then \
			PROXY=\"teleport-cluster.teleport-cluster.svc.cluster.local:443\"; \
		else \
			PROXY=\"teleport.teleport.svc.cluster.local:3080\"; \
		fi; \
		echo \"✅ Using Kubernetes service: \$$PROXY\"; \
	fi; \
	CLUSTER=\$$(grep -E '^\s*cluster_name:' config.yaml 2>/dev/null | sed -E 's/.*cluster_name:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/' | head -1); \
	if [ -z \"\$$CLUSTER\" ] || [ \"\$$CLUSTER\" = \"your-k8s-cluster\" ]; then \
		if [ -n \"$(TELEPORT_CLUSTER_NAME)\" ] && [ \"$(TELEPORT_CLUSTER_NAME)\" != \"your-k8s-cluster\" ]; then \
			CLUSTER=\"$(TELEPORT_CLUSTER_NAME)\"; \
		else \
			echo '❌ TELEPORT_CLUSTER_NAME not found in config.yaml'; \
			exit 1; \
		fi; \
	fi; \
	K8S_NS=\$$(grep -A 2 '^kubernetes:' config.yaml 2>/dev/null | grep -E '^\s*namespace:' | sed -E 's/.*namespace:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/' | head -1); \
	if [ -z \"\$$K8S_NS\" ]; then \
		K8S_NS=\"kubernetes-dashboard\"; \
	fi; \
	TELEPORT_NS=\$$(grep -A 2 '^teleport:' config.yaml 2>/dev/null | grep -E '^\s*namespace:' | sed -E 's/.*namespace:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/' | head -1); \
	if [ -z \"\$$TELEPORT_NS\" ]; then \
		TELEPORT_NS=\"teleport-cluster\"; \
	fi; \
	echo \"✅ Using token: \$$TOKEN\"; \
	echo \"✅ Using proxy: \$$PROXY\"; \
	echo \"✅ Using cluster: \$$CLUSTER\"; \
	echo \"✅ Using namespace: \$$TELEPORT_NS\"; \
	echo '📦 Adding Helm repositories...'; \
	helm repo add teleport https://charts.releases.teleport.dev 2>/dev/null || true; \
	helm repo update; \
	echo '🔧 Installing Teleport Kube Agent...'; \
	TEMP_VALUES=\$$(mktemp); \
	echo \"authToken: \$$TOKEN\" > \$$TEMP_VALUES; \
	echo 'joinParams:' >> \$$TEMP_VALUES; \
	echo '  method: token' >> \$$TEMP_VALUES; \
	echo \"  tokenName: \$$TOKEN\" >> \$$TEMP_VALUES; \
	echo \"proxyAddr: \$$PROXY\" >> \$$TEMP_VALUES; \
	echo \"kubeClusterName: \$$CLUSTER\" >> \$$TEMP_VALUES; \
	echo 'insecureSkipProxyTLSVerify: true' >> \$$TEMP_VALUES; \
	echo 'labels:' >> \$$TEMP_VALUES; \
	echo '  env: dev' >> \$$TEMP_VALUES; \
	echo '  provider: kubernetes' >> \$$TEMP_VALUES; \
	echo 'roles: kube,app' >> \$$TEMP_VALUES; \
	echo 'apps:' >> \$$TEMP_VALUES; \
	echo '- name: kube-dashboard' >> \$$TEMP_VALUES; \
	CLUSTER_IP=\$$(kubectl -n \$$K8S_NS get svc kubernetes-dashboard -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo ''); \
	if [ -z \"\$$CLUSTER_IP\" ]; then \
		CLUSTER_IP=\"https://kubernetes-dashboard.\$$K8S_NS.svc.cluster.local\"; \
	else \
		CLUSTER_IP=\"https://\$$CLUSTER_IP\"; \
	fi; \
	echo \"  uri: \$$CLUSTER_IP\" >> \$$TEMP_VALUES; \
	echo '  insecure_skip_verify: true' >> \$$TEMP_VALUES; \
	echo '  labels:' >> \$$TEMP_VALUES; \
	echo '    env: dev' >> \$$TEMP_VALUES; \
	helm upgrade --install teleport-kube-agent teleport/teleport-kube-agent \
		--create-namespace \
		--namespace \$$TELEPORT_NS \
		-f \$$TEMP_VALUES \
		--wait --timeout=5m || true; \
	rm -f \$$TEMP_VALUES; \
	echo ''; \
	echo '✅ Teleport Kube Agent deployed!'; \
	echo \"📋 Check status: kubectl get pods -n \$$TELEPORT_NS -l app.kubernetes.io/name=teleport-kube-agent\""
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━423:424:Makefile
	@echo ""
	@echo "============================================================"
	@echo ""
	@echo "📋 Summary:"
	@echo "  ✅ Teleport server deployed and running"
	@echo "  ✅ Admin user created"
	@echo "  ✅ Join token generated"
	@echo "  ✅ Port-forward active (https://localhost:3080)"
	@echo "  ✅ Kubernetes Dashboard deployed"
	@echo "  ✅ Teleport agent deployed"
	@echo ""
	@if [ -f /tmp/teleport-admin-invite-url.txt ]; then \
		INVITE_URL=$$(cat /tmp/teleport-admin-invite-url.txt); \
		echo "🔗 Admin Invite URL:"; \
		echo "   $$INVITE_URL"; \
		echo ""; \
		echo "📋 Next Steps:"; \
		echo ""; \
		echo "  1️⃣  Accept the Admin Invite:"; \
		echo "     • Open the URL above in your browser"; \
		echo "     • Set your admin password"; \
		echo ""; \
		echo "  2️⃣  Access Teleport Web Console:"; \
		echo "     • URL: https://localhost:3080"; \
		echo "     • Log in with username: admin"; \
		echo ""; \
		echo "  3️⃣  Check Teleport Agent Status:"; \
		echo "     • Wait 2-3 minutes for the agent to register"; \
		echo "     • Check status: make status"; \
		echo "     • View logs: make logs (select option 2 for Teleport Agent)"; \
		echo ""; \
		echo "  4️⃣  Get Dashboard Access Tokens:"; \
		echo "     • Run: make get-tokens"; \
		echo "     • This will show admin and readonly tokens for Kubernetes Dashboard"; \
		echo ""; \
		echo "  5️⃣  Access Kubernetes Dashboard via Teleport:"; \
		echo "     • In Teleport Web UI, go to: Applications → kube-dashboard"; \
		echo "     • Or access directly via Teleport proxy"; \
		echo ""; \
		echo "  6️⃣  View Logs (if needed):"; \
		echo "     • Teleport Server: make logs (option 1)"; \
		echo "     • Teleport Agent: make logs (option 2)"; \
		echo "     • Kubernetes Dashboard: make logs (option 3)"; \
	else \
		echo "📋 Next Steps:"; \
		echo ""; \
		echo "  1️⃣  Access Teleport Web Console:"; \
		echo "     • URL: https://localhost:3080"; \
		echo "     • Create/reset admin user: make teleport-create-admin"; \
		echo ""; \
		echo "  2️⃣  Check Teleport Agent Status:"; \
		echo "     • Wait 2-3 minutes for the agent to register"; \
		echo "     • Check status: make status"; \
		echo "     • View logs: make logs (select option 2 for Teleport Agent)"; \
		echo ""; \
		echo "  3️⃣  Get Dashboard Access Tokens:"; \
		echo "     • Run: make get-tokens"; \
		echo "     • This will show admin and readonly tokens for Kubernetes Dashboard"; \
		echo ""; \
		echo "  4️⃣  Access Kubernetes Dashboard via Teleport:"; \
		echo "     • In Teleport Web UI, go to: Applications → kube-dashboard"; \
		echo "     • Or access directly via Teleport proxy"; \
		echo ""; \
		echo "  5️⃣  View Logs (if needed):"; \
		echo "     • Teleport Server: make logs (option 1)"; \
		echo "     • Teleport Agent: make logs (option 2)"; \
		echo "     • Kubernetes Dashboard: make logs (option 3)"; \
	fi
	@echo ""
	@echo "💡 To stop port-forward: kill \$$(cat /tmp/teleport-port-forward.pid 2>/dev/null) 2>/dev/null || true"

# Clean up only the Teleport Kube Agent resources
clean-kube-agent:
	@echo "🧹 Cleaning up Teleport Kube Agent resources..."
	@sh -c "set -e; \
	TELEPORT_NS=\$$(grep -A 2 '^teleport:' config.yaml 2>/dev/null | grep -E '^\s*namespace:' | sed -E 's/.*namespace:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/' | head -1); \
	if [ -z \"\$$TELEPORT_NS\" ]; then \
		TELEPORT_NS=\"teleport-cluster\"; \
	fi; \
	echo \"📋 Using namespace: \$$TELEPORT_NS\"; \
	echo ''; \
	echo 'Step 1/4: Uninstalling Helm release...'; \
	helm uninstall teleport-kube-agent --namespace \$$TELEPORT_NS 2>/dev/null || echo '  ⚠️  Helm release not found (may already be removed)'; \
	echo ''; \
	echo 'Step 2/4: Deleting remaining pods and statefulsets...'; \
	kubectl delete pod -n \$$TELEPORT_NS -l app.kubernetes.io/name=teleport-kube-agent --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete pod -n \$$TELEPORT_NS -l app=teleport-kube-agent --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete statefulset -n \$$TELEPORT_NS teleport-kube-agent --ignore-not-found=true 2>/dev/null || true; \
	echo '  ✅ Pods and StatefulSets cleaned up'; \
	echo ''; \
	echo 'Step 3/4: Deleting secrets...'; \
	kubectl delete secret -n \$$TELEPORT_NS -l app.kubernetes.io/name=teleport-kube-agent --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete secret -n \$$TELEPORT_NS teleport-kube-agent-join-token --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete secret -n \$$TELEPORT_NS teleport-kube-agent-0-state --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete secret -n \$$TELEPORT_NS -l 'app.kubernetes.io/instance=teleport-kube-agent' --ignore-not-found=true 2>/dev/null || true; \
	echo '  ✅ Secrets cleaned up'; \
	echo ''; \
	echo 'Step 4/4: Deleting configmaps...'; \
	kubectl delete configmap -n \$$TELEPORT_NS teleport-kube-agent --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete configmap -n \$$TELEPORT_NS -l app.kubernetes.io/name=teleport-kube-agent --ignore-not-found=true 2>/dev/null || true; \
	echo '  ✅ ConfigMaps cleaned up'; \
	echo ''; \
	echo '✅ Teleport Kube Agent cleanup complete!'"
	@echo ""
	@echo "📋 Cleaned up:"
	@echo "  ✅ Helm release uninstalled"
	@echo "  ✅ Pods and StatefulSets deleted"
	@echo "  ✅ Secrets deleted"
	@echo "  ✅ ConfigMaps deleted"
	@echo ""

# Clean up all deployments (Teleport server, Dashboard, Agent, port-forwards)
helm-clean:
	@echo "🧹 Cleaning up all resources..."
	@echo ""
	@echo "Step 1/5: Stopping Teleport port-forward..."
	@if [ -f /tmp/teleport-port-forward.pid ]; then \
		PID=$$(cat /tmp/teleport-port-forward.pid 2>/dev/null || echo ""); \
		if [ -n "$$PID" ] && kill -0 $$PID 2>/dev/null; then \
			kill $$PID 2>/dev/null || true; \
			echo "✅ Stopped port-forward (PID: $$PID)"; \
		fi; \
		rm -f /tmp/teleport-port-forward.pid; \
	fi; \
	pkill -f "kubectl port-forward.*teleport.*3080" 2>/dev/null || true; \
	echo "✅ Port-forward cleanup complete"
	@echo ""
	@echo "Step 2/5: Uninstalling Helm releases..."
	@K8S_NS=$$(grep -A 2 "^kubernetes:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E 's/.*namespace:[[:space:]]*["'\'']?([^"'\'']+)["'\'']?.*/\1/' | head -1); \
	if [ -z "$$K8S_NS" ]; then \
		K8S_NS="kubernetes-dashboard"; \
	fi; \
	TELEPORT_NS=$$(grep -A 2 "^teleport:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E 's/.*namespace:[[:space:]]*["'\'']?([^"'\'']+)["'\'']?.*/\1/' | head -1); \
	if [ -z "$$TELEPORT_NS" ]; then \
		TELEPORT_NS="teleport-cluster"; \
	fi; \
	echo "🗑️  Uninstalling Teleport Kube Agent from namespace: $$TELEPORT_NS"; \
	helm uninstall teleport-kube-agent --namespace $$TELEPORT_NS 2>/dev/null || true; \
	echo "🗑️  Uninstalling Kubernetes Dashboard from namespace: $$K8S_NS"; \
	helm uninstall kubernetes-dashboard --namespace $$K8S_NS 2>/dev/null || true; \
	echo "🗑️  Uninstalling Teleport Cluster from namespace: teleport-cluster"; \
	helm uninstall teleport-cluster --namespace teleport-cluster 2>/dev/null || true; \
	echo "✅ Helm releases uninstalled"
	@echo ""
	@echo "Step 3/5: Removing Teleport server..."
	@helm uninstall teleport-cluster --namespace teleport-cluster 2>/dev/null || true
	@echo "✅ Teleport server removed"
	@echo ""
	@echo "Step 4/5: Deleting namespaces..."
	@K8S_NS=$$(grep -A 2 "^kubernetes:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E 's/.*namespace:[[:space:]]*["'\'']?([^"'\'']+)["'\'']?.*/\1/' | head -1); \
	if [ -z "$$K8S_NS" ]; then \
		K8S_NS="kubernetes-dashboard"; \
	fi; \
	TELEPORT_NS=$$(grep -A 2 "^teleport:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E 's/.*namespace:[[:space:]]*["'\'']?([^"'\'']+)["'\'']?.*/\1/' | head -1); \
	if [ -z "$$TELEPORT_NS" ]; then \
		TELEPORT_NS="teleport-cluster"; \
	fi; \
	echo "🗑️  Deleting namespace: $$TELEPORT_NS"; \
	kubectl delete namespace $$TELEPORT_NS 2>/dev/null || true; \
	echo "🗑️  Deleting namespace: $$K8S_NS"; \
	kubectl delete namespace $$K8S_NS 2>/dev/null || true; \
	echo "🗑️  Deleting namespace: teleport"; \
	kubectl delete namespace teleport 2>/dev/null || true; \
	echo "✅ Namespaces deleted"
	@echo ""
	@echo "Step 5/5: Removing RBAC resources..."
	@kubectl delete -f k8s/rbac.yaml 2>/dev/null || true
	@echo "✅ RBAC resources removed"
	@echo ""
	@echo "✅ Full cleanup complete!"
	@echo ""
	@echo "📋 Cleaned up:"
	@echo "  ✅ Teleport port-forward stopped"
	@echo "  ✅ Helm releases uninstalled"
	@echo "  ✅ Teleport server removed"
	@echo "  ✅ All namespaces deleted"
	@echo "  ✅ RBAC resources removed"

# Show Helm deployment status
helm-status:
	@echo "📊 Helm Deployment Status:"
	@K8S_NS=$$(grep -A 2 "^kubernetes:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E 's/.*namespace:[[:space:]]*["'\'']?([^"'\'']+)["'\'']?.*/\1/' | head -1); \
	if [ -z "$$K8S_NS" ]; then \
		K8S_NS="kubernetes-dashboard"; \
	fi; \
	TELEPORT_NS=$$(grep -A 2 "^teleport:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E 's/.*namespace:[[:space:]]*["'\'']?([^"'\'']+)["'\'']?.*/\1/' | head -1); \
	if [ -z "$$TELEPORT_NS" ]; then \
		TELEPORT_NS="teleport-cluster"; \
	fi; \
	echo ""; \
	echo "Kubernetes Dashboard (namespace: $$K8S_NS):"; \
	helm status kubernetes-dashboard --namespace $$K8S_NS 2>/dev/null || echo "  Not installed"; \
	echo ""; \
	echo "Teleport Kube Agent (namespace: $$TELEPORT_NS):"; \
	helm status teleport-kube-agent --namespace $$TELEPORT_NS 2>/dev/null || echo "  Not installed"

# Get dashboard access tokens
get-tokens:
	@echo "🔑 Dashboard Access Tokens:"
	@echo ""
	@echo "Admin Token:"
	@kubectl get secret dashboard-admin-token -n $(K8S_NAMESPACE) -o jsonpath="{.data.token}" 2>/dev/null | base64 -d || echo "  Secret not found"
	@echo ""
	@echo ""
	@echo "Read-only Token:"
	@kubectl get secret dashboard-readonly-token -n $(K8S_NAMESPACE) -o jsonpath="{.data.token}" 2>/dev/null | base64 -d || echo "  Secret not found"
	@echo ""

# Get dashboard ClusterIP
get-clusterip:
	@echo "🌐 Dashboard ClusterIP:"
	@kubectl -n $(K8S_NAMESPACE) get svc kubernetes-dashboard -o jsonpath="{.spec.clusterIP}" 2>/dev/null || echo "  Service not found"
	@echo ""

# Show overall status
status:
	@echo "📊 Overall Status:"
	@echo ""
	@echo "Namespaces:"
	@kubectl get namespaces | grep -E "$(K8S_NAMESPACE)|$(TELEPORT_NAMESPACE)" || echo "  No namespaces found"
	@echo ""
	@echo "Pods in $(K8S_NAMESPACE):"
	@kubectl get pods -n $(K8S_NAMESPACE) || echo "  No pods found"
	@echo ""
	@echo "Pods in $(TELEPORT_NAMESPACE):"
	@kubectl get pods -n $(TELEPORT_NAMESPACE) || echo "  No pods found"
	@echo ""
	@echo "Services:"
	@kubectl get svc -n $(K8S_NAMESPACE) | grep kubernetes-dashboard || echo "  No services found"

# Show dashboard logs (follow mode by default)
dashboard-logs:
	@echo "📋 Following Kubernetes Dashboard Logs (Press Ctrl-C to exit):"
	@echo ""
	@sh -c '\
	K8S_NS=$$(grep -A 2 "^kubernetes:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E "s/.*namespace:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/" | head -1); \
	if [ -z "$$K8S_NS" ]; then \
		K8S_NS="kubernetes-dashboard"; \
	fi; \
	POD=$$(kubectl -n $$K8S_NS get pods --no-headers 2>/dev/null | grep -i dashboard | head -1 | cut -d" " -f1 || echo ""); \
	if [ -z "$$POD" ]; then \
		POD=$$(kubectl -n $$K8S_NS get pods -l app.kubernetes.io/name=kubernetes-dashboard -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo ""); \
	fi; \
	if [ -z "$$POD" ]; then \
		POD=$$(kubectl -n $$K8S_NS get pods -l app=kubernetes-dashboard -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo ""); \
	fi; \
	if [ -z "$$POD" ]; then \
		echo "  No dashboard pods found in namespace: $$K8S_NS"; \
		echo "  Available pods:"; \
		kubectl -n $$K8S_NS get pods 2>/dev/null || echo "    (namespace may not exist)"; \
		exit 1; \
	else \
		echo "📦 Pod: $$POD"; \
		echo ""; \
		kubectl logs -n $$K8S_NS $$POD -f || echo "  Failed to retrieve logs"; \
	fi'

# Show Teleport agent logs (follow mode by default)
teleport-agent-logs:
	@echo "📋 Following Teleport Kube Agent Logs (Press Ctrl-C to exit):"
	@echo ""
	@sh -c '\
	TELEPORT_NS=$$(grep -A 2 "^teleport:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E "s/.*namespace:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/" | head -1); \
	if [ -z "$$TELEPORT_NS" ]; then \
		TELEPORT_NS="teleport-cluster"; \
	fi; \
	POD=$$(kubectl -n $$TELEPORT_NS get pods --no-headers 2>/dev/null | grep -i teleport | head -1 | cut -d" " -f1 || echo ""); \
	if [ -z "$$POD" ]; then \
		POD=$$(kubectl -n $$TELEPORT_NS get pods -l app.kubernetes.io/name=teleport-kube-agent -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo ""); \
	fi; \
	if [ -z "$$POD" ]; then \
		POD=$$(kubectl -n $$TELEPORT_NS get pods -l app=teleport-kube-agent -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo ""); \
	fi; \
	if [ -z "$$POD" ]; then \
		echo "  No Teleport agent pods found in namespace: $$TELEPORT_NS"; \
		echo "  Available pods:"; \
		kubectl -n $$TELEPORT_NS get pods 2>/dev/null || echo "    (namespace may not exist)"; \
		exit 1; \
	else \
		echo "📦 Pod: $$POD"; \
		echo ""; \
		kubectl logs -n $$TELEPORT_NS $$POD -f || echo "  Failed to retrieve logs"; \
	fi'

# Show logs (interactive menu)
logs:
	@echo "📋 Which logs would you like to view?"
	@echo ""
	@echo "  1) Teleport Server"
	@echo "  2) Teleport Agent"
	@echo "  3) Kubernetes Dashboard"
	@echo "  4) All (show status of all components)"
	@echo ""
	@sh -c 'read -p "Select an option (1-4): " choice; \
	case "$$choice" in \
		1) \
			echo ""; \
			echo "📋 Following Teleport Server Logs (Press Ctrl-C to exit):"; \
			echo ""; \
			POD=$$(kubectl -n teleport-cluster get pods -l app.kubernetes.io/name=teleport-cluster,app.kubernetes.io/component=auth -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo ""); \
			if [ -n "$$POD" ]; then \
				NS="teleport-cluster"; \
				echo "📦 Auth Pod: $$POD"; \
				echo ""; \
				kubectl logs -n $$NS $$POD -f || echo "  Failed to retrieve logs"; \
			else \
				POD=$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo ""); \
				if [ -z "$$POD" ]; then \
					echo "❌ Teleport server pod not found"; \
					echo "   Run: make deploy-teleport"; \
					exit 1; \
				else \
					NS="teleport"; \
					echo "📦 Pod: $$POD"; \
					echo ""; \
					kubectl logs -n $$NS $$POD -f || echo "  Failed to retrieve logs"; \
				fi; \
			fi; \
			;; \
		2) \
			echo ""; \
			echo "📋 Following Teleport Kube Agent Logs (Press Ctrl-C to exit):"; \
			echo ""; \
			TELEPORT_NS=$$(grep -A 2 "^teleport:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E "s/.*namespace:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/" | head -1); \
			if [ -z "$$TELEPORT_NS" ]; then \
				TELEPORT_NS="teleport-cluster"; \
			fi; \
			POD=$$(kubectl -n $$TELEPORT_NS get pods --no-headers 2>/dev/null | grep -i teleport | head -1 | cut -d" " -f1 || echo ""); \
			if [ -z "$$POD" ]; then \
				POD=$$(kubectl -n $$TELEPORT_NS get pods -l app.kubernetes.io/name=teleport-kube-agent -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo ""); \
			fi; \
			if [ -z "$$POD" ]; then \
				POD=$$(kubectl -n $$TELEPORT_NS get pods -l app=teleport-kube-agent -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo ""); \
			fi; \
			if [ -z "$$POD" ]; then \
				echo "  No Teleport agent pods found in namespace: $$TELEPORT_NS"; \
				echo "  Available pods:"; \
				kubectl -n $$TELEPORT_NS get pods 2>/dev/null || echo "    (namespace may not exist)"; \
				exit 1; \
			else \
				echo "📦 Pod: $$POD"; \
				echo ""; \
				kubectl logs -n $$TELEPORT_NS $$POD -f || echo "  Failed to retrieve logs"; \
			fi; \
			;; \
		3) \
			echo ""; \
			echo "📋 Following Kubernetes Dashboard Logs (Press Ctrl-C to exit):"; \
			echo ""; \
			K8S_NS=$$(grep -A 2 "^kubernetes:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E "s/.*namespace:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/" | head -1); \
			if [ -z "$$K8S_NS" ]; then \
				K8S_NS="kubernetes-dashboard"; \
			fi; \
			POD=$$(kubectl -n $$K8S_NS get pods --no-headers 2>/dev/null | grep -i dashboard | head -1 | cut -d" " -f1 || echo ""); \
			if [ -z "$$POD" ]; then \
				POD=$$(kubectl -n $$K8S_NS get pods -l app.kubernetes.io/name=kubernetes-dashboard -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo ""); \
			fi; \
			if [ -z "$$POD" ]; then \
				POD=$$(kubectl -n $$K8S_NS get pods -l app=kubernetes-dashboard -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo ""); \
			fi; \
			if [ -z "$$POD" ]; then \
				echo "  No dashboard pods found in namespace: $$K8S_NS"; \
				echo "  Available pods:"; \
				kubectl -n $$K8S_NS get pods 2>/dev/null || echo "    (namespace may not exist)"; \
				exit 1; \
			else \
				echo "📦 Pod: $$POD"; \
				echo ""; \
				kubectl logs -n $$K8S_NS $$POD -f || echo "  Failed to retrieve logs"; \
			fi; \
			;; \
		4) \
			echo ""; \
			echo "📊 All Components Status:"; \
			echo ""; \
			echo "=== Teleport Server (Helm) ==="; \
			kubectl get pods -n teleport-cluster -l app.kubernetes.io/name=teleport-cluster 2>/dev/null || echo "  Not deployed"; \
			echo ""; \
			echo "=== Teleport Server (Legacy) ==="; \
			kubectl get pods -n teleport -l app=teleport,component=server 2>/dev/null || echo "  Not deployed"; \
			echo ""; \
			TELEPORT_NS=$$(grep -A 2 "^teleport:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E "s/.*namespace:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/" | head -1); \
			if [ -z "$$TELEPORT_NS" ]; then \
				TELEPORT_NS="teleport-cluster"; \
			fi; \
			echo "=== Teleport Agent ==="; \
			kubectl get pods -n $$TELEPORT_NS -l app.kubernetes.io/name=teleport-kube-agent 2>/dev/null || echo "  Not deployed"; \
			echo ""; \
			K8S_NS=$$(grep -A 2 "^kubernetes:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E "s/.*namespace:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/" | head -1); \
			if [ -z "$$K8S_NS" ]; then \
				K8S_NS="kubernetes-dashboard"; \
			fi; \
			echo "=== Kubernetes Dashboard ==="; \
			kubectl get pods -n $$K8S_NS -l app.kubernetes.io/name=kubernetes-dashboard 2>/dev/null || echo "  Not deployed"; \
			;; \
		*) \
			echo ""; \
			echo "❌ Invalid option. Please select 1, 2, 3, or 4."; \
			exit 1; \
			;; \
	esac'

# Deploy Teleport server to Kubernetes using official Helm chart
deploy-teleport: check-minikube
	@echo "🚀 Deploying Teleport server to Kubernetes using official Helm chart..."
	@echo "📦 Adding Teleport Helm repository..."
	@helm repo add teleport https://charts.releases.teleport.dev 2>/dev/null || true
	@helm repo update
	@echo "📁 Creating namespace..."
	@kubectl create namespace teleport-cluster 2>/dev/null || true
	@kubectl label namespace teleport-cluster 'pod-security.kubernetes.io/enforce=baseline' 2>/dev/null || true
	@echo "⚙️  Creating Helm values file for local testing..."
	@printf 'clusterName: teleport.local\nproxyListenerMode: multiplex\nacme: false\nservice:\n  type: ClusterIP\n  annotations: {}\nhighAvailability:\n  replicaCount: 1\n  podDisruptionBudget:\n    enabled: false\nproxy:\n  publicAddr: teleport-cluster.teleport-cluster.svc.cluster.local:443\n  teleportConfig:\n    proxy_service:\n      public_addr: teleport-cluster.teleport-cluster.svc.cluster.local:443\n  extraArgs:\n  - "--insecure"\n' > /tmp/teleport-cluster-values.yaml
	@echo "🔧 Installing Teleport cluster Helm chart..."
	@helm upgrade --install teleport-cluster teleport/teleport-cluster \
		--version 18.6.0 \
		--namespace teleport-cluster \
		--values /tmp/teleport-cluster-values.yaml \
		--wait --timeout=5m || true
	@rm -f /tmp/teleport-cluster-values.yaml
	@echo "⏳ Waiting for Teleport pods to be ready..."
	@kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=teleport-cluster -n teleport-cluster --timeout=300s 2>/dev/null || \
		(echo "⚠️  Pods may still be starting. Check status with: kubectl get pods -n teleport-cluster" && sleep 10)
	@echo "✅ Teleport server deployed!"
	@echo ""
	@echo "📋 Next steps:"
	@echo "  1. Port-forward to access web UI: make teleport-port-forward"
	@echo "  2. Access at: https://localhost:3080"
	@echo "  3. Create admin user: make teleport-create-admin"

# Port-forward Teleport web UI
teleport-port-forward:
	@echo "🌐 Port-forwarding Teleport web UI to localhost:3080 (Press Ctrl-C to exit):"
	@echo ""
	@if pgrep -f "kubectl port-forward.*teleport.*3080" > /dev/null; then \
		echo "⚠️  Port-forward already running. Stopping existing one..."; \
		pkill -f "kubectl port-forward.*teleport.*3080" 2>/dev/null || true; \
		rm -f /tmp/teleport-port-forward.pid; \
		sleep 1; \
	fi; \
	# Try teleport-cluster namespace first (Helm chart), fallback to teleport (manual)
	if kubectl get svc teleport-cluster -n teleport-cluster >/dev/null 2>&1; then \
		kubectl port-forward -n teleport-cluster svc/teleport-cluster 3080:443; \
	elif kubectl get svc teleport -n teleport >/dev/null 2>&1; then \
		kubectl port-forward -n teleport svc/teleport 3080:3080; \
	else \
		echo "❌ Teleport service not found. Run 'make deploy-teleport' first."; \
		exit 1; \
	fi

# Stop Teleport port-forward
teleport-stop-port-forward:
	@echo "🛑 Stopping Teleport port-forward..."
	@if [ -f /tmp/teleport-port-forward.pid ]; then \
		PID=$$(cat /tmp/teleport-port-forward.pid 2>/dev/null || echo ""); \
		if [ -n "$$PID" ] && kill -0 $$PID 2>/dev/null; then \
			kill $$PID 2>/dev/null || true; \
			echo "✅ Stopped port-forward (PID: $$PID)"; \
		fi; \
		rm -f /tmp/teleport-port-forward.pid; \
	fi; \
	pkill -f "kubectl port-forward.*teleport.*3080" 2>/dev/null && echo "✅ Port-forward stopped" || echo "⚠️  No port-forward process found"

# Check Teleport server status
teleport-status:
	@echo "📊 Teleport Server Status:"
	@echo ""
	@echo "=== Teleport Cluster (Helm) ==="
	@kubectl get pods -n teleport-cluster -l app.kubernetes.io/name=teleport-cluster 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "Services:"
	@kubectl get svc -n teleport-cluster 2>/dev/null || echo "  No services found"
	@echo ""
	@echo "=== Legacy Teleport (Manual) ==="
	@kubectl get pods -n teleport -l app=teleport,component=server 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "Services:"
	@kubectl get svc -n teleport 2>/dev/null || echo "  No services found"

# View Teleport server logs
teleport-logs:
	@echo "📋 Following Teleport Server Logs (Press Ctrl-C to exit):"
	@echo ""
	@POD=$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""); \
	if [ -z "$$POD" ]; then \
		echo "❌ Teleport server pod not found"; \
		echo "   Run: make deploy-teleport"; \
		exit 1; \
	else \
		echo "📦 Pod: $$POD"; \
		echo ""; \
		kubectl logs -n teleport $$POD -f; \
	fi

# Clean up Teleport server
teleport-clean:
	@echo "🧹 Cleaning up Teleport server..."
	@echo "🗑️  Uninstalling Teleport Helm chart..."
	@helm uninstall teleport-cluster --namespace teleport-cluster 2>/dev/null || true
	@echo "🗑️  Deleting namespace..."
	@kubectl delete namespace teleport-cluster 2>/dev/null || true
	@kubectl delete namespace teleport 2>/dev/null || true
	@echo "✅ Teleport server removed"

# Create admin user in Teleport
teleport-create-admin:
	@echo "👤 Creating admin user in Teleport..."
	@POD=$$(kubectl -n teleport-cluster get pods -l app.kubernetes.io/name=teleport-cluster,app.kubernetes.io/component=auth -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""); \
	if [ -n "$$POD" ]; then \
		NS="teleport-cluster"; \
	elif [ -n "$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")" ]; then \
		POD=$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}'); \
		NS="teleport"; \
	else \
		echo "❌ Teleport server pod not found"; \
		echo "   Run: make deploy-teleport"; \
		exit 1; \
	fi; \
	if [ -z "$$POD" ]; then \
		echo "❌ Teleport server pod not found"; \
		echo "   Run: make deploy-teleport"; \
		exit 1; \
	else \
		OUTPUT=$$(kubectl exec -n $$NS $$POD -- tctl users add admin --roles=editor,access --logins=root,admin 2>&1 || \
		kubectl exec -n $$NS $$POD -- tctl users add admin --roles=editor,access --logins root,admin 2>&1 || echo ""); \
		if [ -n "$$OUTPUT" ]; then \
			echo "$$OUTPUT" | sed 's|https://teleport\.local:443|https://localhost:3080|g' | sed 's|teleport\.local:443|localhost:3080|g'; \
		fi; \
		echo "✅ Admin user created"; \
		echo "📋 Next steps:"; \
		echo "  1. Reset password: kubectl exec -n $$NS $$POD -- tctl users reset admin"; \
		echo "  2. Or use: make teleport-delete-admin (if user exists)"; \
	fi

# Delete admin user from Teleport
teleport-delete-admin:
	@echo "🗑️  Deleting admin user from Teleport..."
	@POD=$$(kubectl -n teleport-cluster get pods -l app.kubernetes.io/name=teleport-cluster,app.kubernetes.io/component=auth -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""); \
	if [ -n "$$POD" ]; then \
		NS="teleport-cluster"; \
	elif [ -n "$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")" ]; then \
		POD=$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}'); \
		NS="teleport"; \
	else \
		echo "❌ Teleport server pod not found"; \
		echo "   Run: make deploy-teleport"; \
		exit 1; \
	fi; \
	if [ -z "$$POD" ]; then \
		echo "❌ Teleport server pod not found"; \
		echo "   Run: make deploy-teleport"; \
		exit 1; \
	else \
		kubectl exec -n $$NS $$POD -- tctl users rm admin 2>/dev/null || echo "⚠️  User may not exist"; \
		echo "✅ Admin user deleted"; \
	fi

# Create readonly user in Teleport
teleport-create-readonly:
	@echo "👤 Creating readonly user in Teleport..."
	@POD=$$(kubectl -n teleport-cluster get pods -l app.kubernetes.io/name=teleport-cluster,app.kubernetes.io/component=auth -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""); \
	if [ -n "$$POD" ]; then \
		NS="teleport-cluster"; \
	elif [ -n "$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")" ]; then \
		POD=$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}'); \
		NS="teleport"; \
	else \
		echo "❌ Teleport server pod not found"; \
		echo "   Run: make deploy-teleport"; \
		exit 1; \
	fi; \
	if [ -z "$$POD" ]; then \
		echo "❌ Teleport server pod not found"; \
		echo "   Run: make deploy-teleport"; \
		exit 1; \
	else \
		kubectl exec -n $$NS $$POD -- tctl users add readonly --roles=access --logins=readonly 2>/dev/null || \
		kubectl exec -n $$NS $$POD -- tctl users add readonly --roles=access --logins readonly 2>/dev/null || true; \
		echo "✅ Readonly user created"; \
		echo "📋 Next steps:"; \
		echo "  1. Reset password: kubectl exec -n $$NS $$POD -- tctl users reset readonly"; \
		echo "  2. Or use: make teleport-delete-readonly (if user exists)"; \
	fi

# Delete readonly user from Teleport
teleport-delete-readonly:
	@echo "🗑️  Deleting readonly user from Teleport..."
	@POD=$$(kubectl -n teleport-cluster get pods -l app.kubernetes.io/name=teleport-cluster,app.kubernetes.io/component=auth -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""); \
	if [ -n "$$POD" ]; then \
		NS="teleport-cluster"; \
	elif [ -n "$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")" ]; then \
		POD=$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}'); \
		NS="teleport"; \
	else \
		echo "❌ Teleport server pod not found"; \
		echo "   Run: make deploy-teleport"; \
		exit 1; \
	fi; \
	if [ -z "$$POD" ]; then \
		echo "❌ Teleport server pod not found"; \
		echo "   Run: make deploy-teleport"; \
		exit 1; \
	else \
		kubectl exec -n $$NS $$POD -- tctl users rm readonly 2>/dev/null || echo "⚠️  User may not exist"; \
		echo "✅ Readonly user deleted"; \
	fi

# Generate Teleport join token
generate-token:
	@echo "🔑 Generating Teleport join token..."
	@if command -v tctl >/dev/null 2>&1; then \
		echo "✅ Using tctl from host..."; \
		TOKEN_OUTPUT=$$(tctl tokens add --type=kube,app --ttl=24h 2>&1); \
		TOKEN_EXIT=$$?; \
		if [ $$TOKEN_EXIT -eq 0 ]; then \
			TOKEN=$$(echo "$$TOKEN_OUTPUT" | grep -oE '[a-f0-9]{32}' | head -1); \
			if [ -n "$$TOKEN" ]; then \
				echo "✅ Generated token: $$TOKEN"; \
				if [ -f config.yaml ]; then \
					sed -i.bak "s/join_token:.*/join_token: \"$$TOKEN\"/" config.yaml && rm -f config.yaml.bak || \
					sed -i '' "s/join_token:.*/join_token: \"$$TOKEN\"/" config.yaml; \
					echo "✅ Updated config.yaml with join token"; \
				fi; \
				echo "⚠️  Token expires in 24 hours. For production, use longer TTL or rotate regularly."; \
			else \
				echo "❌ Failed to extract token from output"; \
				echo "Output: $$TOKEN_OUTPUT"; \
				exit 1; \
			fi; \
		else \
			echo "❌ Token generation failed"; \
			echo "Output: $$TOKEN_OUTPUT"; \
			exit 1; \
		fi; \
	else \
		POD=$$(kubectl -n teleport-cluster get pods -l app.kubernetes.io/name=teleport-cluster,app.kubernetes.io/component=auth -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""); \
		if [ -n "$$POD" ]; then \
			NS="teleport-cluster"; \
		elif [ -n "$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")" ]; then \
			POD=$$(kubectl -n teleport get pods -l app=teleport,component=server -o jsonpath='{.items[0].metadata.name}'); \
			NS="teleport"; \
		else \
			POD=""; \
			NS=""; \
		fi; \
		if [ -n "$$POD" ] && [ -n "$$NS" ]; then \
			echo "✅ Using tctl from Teleport Kubernetes pod..."; \
			TOKEN_OUTPUT=$$(kubectl exec -n $$NS $$POD -- tctl tokens add --type=kube,app --ttl=24h 2>&1); \
			TOKEN_EXIT=$$?; \
			if [ $$TOKEN_EXIT -eq 0 ]; then \
				TOKEN=$$(echo "$$TOKEN_OUTPUT" | grep -oE '[a-f0-9]{32}' | head -1); \
				if [ -n "$$TOKEN" ]; then \
					echo "✅ Generated token: $$TOKEN"; \
					if [ -f config.yaml ]; then \
						sed -i.bak "s/join_token:.*/join_token: \"$$TOKEN\"/" config.yaml && rm -f config.yaml.bak || \
						sed -i '' "s/join_token:.*/join_token: \"$$TOKEN\"/" config.yaml; \
						echo "✅ Updated config.yaml with join token"; \
					fi; \
					echo "⚠️  Token expires in 24 hours. For production, use longer TTL or rotate regularly."; \
				else \
					echo "❌ Failed to extract token from output"; \
					echo "Output: $$TOKEN_OUTPUT"; \
					exit 1; \
				fi; \
			else \
				echo "❌ Token generation failed"; \
				echo "Output: $$TOKEN_OUTPUT"; \
				exit 1; \
			fi; \
		else \
			echo "❌ tctl not found and Teleport server is not running in Kubernetes"; \
			echo "   Please either:"; \
			echo "   1. Install tctl: https://goteleport.com/docs/installation/"; \
			echo "   2. Or run: make deploy-teleport"; \
			exit 1; \
		fi; \
	fi
