# Kubernetes Dashboard Manager with Teleport
# Makefile for easy project management

# Load configuration from config.yaml if available, otherwise use env vars
TELEPORT_PROXY_ADDR ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep proxy_addr | cut -d'"' -f2 | cut -d'"' -f1 || echo ""; fi)
TELEPORT_CLUSTER_NAME ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep cluster_name | cut -d'"' -f2 | cut -d'"' -f1 || echo ""; fi)
TELEPORT_JOIN_TOKEN ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep join_token | cut -d'"' -f2 | cut -d'"' -f1 || echo ""; fi)
TELEPORT_NAMESPACE ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^teleport:" config.yaml | grep -A 1 "namespace:" | grep -v "^teleport:" | cut -d'"' -f2 | cut -d'"' -f1 || echo "teleport-cluster"; fi)
K8S_NAMESPACE ?= $(shell if [ -f config.yaml ]; then grep -A 1 "^kubernetes:" config.yaml | grep namespace | cut -d'"' -f2 | cut -d'"' -f1 || echo "kubernetes-dashboard"; fi)

.PHONY: help config setup-minikube check-minikube check-prerequisites start-minikube stop-minikube reset-minikube helm-deploy helm-clean helm-status get-tokens get-clusterip status logs debug-dashboard

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
	@echo "  4. make helm-deploy (does everything automatically!)"
	@echo ""
	@echo "That's it! The deployment will:"
	@echo "  - Deploy Teleport server to Kubernetes"
	@echo "  - Create admin user"
	@echo "  - Generate join token"
	@echo "  - Start port-forward to localhost:443"
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
	@echo "🔍 Checking prerequisites..."
	@echo "📦 Checking minikube addons..."
	@if minikube addons list 2>/dev/null | grep -q "ingress.*enabled"; then \
		echo "✅ Ingress addon is enabled"; \
	else \
		echo "❌ Ingress addon is not enabled. Run: minikube addons enable ingress"; \
		exit 1; \
	fi
	@if minikube addons list 2>/dev/null | grep -q "ingress-dns.*enabled"; then \
		echo "✅ Ingress-DNS addon is enabled"; \
	else \
		echo "❌ Ingress-DNS addon is not enabled. Run: minikube addons enable ingress-dns"; \
		exit 1; \
	fi
	@echo "🔍 Checking /etc/hosts DNS mappings..."
	@if grep -q "teleport-cluster.teleport-cluster.svc.cluster.local" /etc/hosts 2>/dev/null; then \
		echo "✅ Found teleport-cluster DNS mapping in /etc/hosts"; \
	else \
		echo "❌ Missing teleport-cluster DNS mapping in /etc/hosts"; \
		echo "   Add: 127.0.0.1 teleport-cluster.teleport-cluster.svc.cluster.local"; \
		exit 1; \
	fi
	@if grep -q "dashboard.teleport-cluster.teleport-cluster.svc.cluster.local" /etc/hosts 2>/dev/null; then \
		echo "✅ Found dashboard DNS mapping in /etc/hosts"; \
	else \
		echo "❌ Missing dashboard DNS mapping in /etc/hosts"; \
		echo "   Add: 127.0.0.1 dashboard.teleport-cluster.teleport-cluster.svc.cluster.local"; \
		exit 1; \
	fi

# Deploy using Helm (automated full deployment)
helm-deploy: check-minikube check-prerequisites
	@echo "🚀 Starting full deployment (RBAC + Teleport + Dashboard + Agent)..."
	@echo ""
	@echo "Step 1/6: Deploying RBAC resources..."
	@echo "🔐 Deploying RBAC resources..."
	@kubectl apply -f k8s/namespace.yaml
	@kubectl apply -f k8s/rbac.yaml
	@echo "⏳ Waiting for tokens to be generated..."
	@sleep 5
	@echo "✅ RBAC resources deployed!"
	@echo ""
	@echo "Step 2/6: Deploying Teleport server to Kubernetes..."
	@echo "🚀 Deploying Teleport server to Kubernetes using official Helm chart..."
	@echo "📦 Adding Teleport Helm repository..."
	@helm repo add teleport https://charts.releases.teleport.dev 2>/dev/null || true
	@helm repo update
	@echo "📁 Creating namespace..."
	@kubectl create namespace teleport-cluster 2>/dev/null || true
	@kubectl label namespace teleport-cluster 'pod-security.kubernetes.io/enforce=baseline' 2>/dev/null || true
	@echo "⚙️  Creating Helm values file for local testing..."
	@printf 'clusterName: minikube\nproxyListenerMode: multiplex\nacme: false\npublicAddr:\n  - teleport-cluster.teleport-cluster.svc.cluster.local:443\nextraArgs:\n- "--insecure"\nauth:\n  service:\n    enabled: true\n    type: ClusterIP\nhighAvailability:\n  replicaCount: 1\n  podDisruptionBudget:\n    enabled: false\nlog:\n  level: DEBUG\n' > /tmp/teleport-cluster-values.yaml
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
	@echo "Step 3/6: Setting up Teleport admin user with Kubernetes access..."
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
	echo "🔐 Creating k8s-admin role with Kubernetes access..."; \
	printf "kind: role\nversion: v7\nmetadata:\n  name: k8s-admin\nspec:\n  allow:\n    kubernetes_labels:\n      \"*\": \"*\"\n    kubernetes_groups:\n    - system:masters\n" | \
	kubectl exec -n $$NS $$POD -i -- tctl create -f - 2>/dev/null || \
	printf "kind: role\nversion: v7\nmetadata:\n  name: k8s-admin\nspec:\n  allow:\n    kubernetes_labels:\n      \"*\": \"*\"\n    kubernetes_groups:\n    - system:masters\n" | \
	kubectl exec -n $$NS $$POD -i -- tctl update -f - 2>/dev/null && echo "✅ k8s-admin role created/updated" || echo "⚠️  k8s-admin role creation failed"; \
	USER_EXISTS=$$(kubectl exec -n $$NS $$POD -- tctl users ls 2>/dev/null | grep -q "admin" && echo "yes" || echo "no"); \
	if [ "$$USER_EXISTS" = "no" ]; then \
		echo "👤 Creating admin user..."; \
		OUTPUT=$$(kubectl exec -n $$NS $$POD -- tctl users add admin --roles=editor,access,k8s-admin --logins=root,minikube 2>&1 || \
		kubectl exec -n $$NS $$POD -- tctl users add admin --roles=editor,access,k8s-admin --logins root,minikube 2>&1 || echo ""); \
		if [ -n "$$OUTPUT" ]; then \
			INVITE_URL=$$(echo "$$OUTPUT" | grep -oE 'https://[^[:space:]]+/web/invite/[^[:space:]]+' | head -1); \
			if [ -n "$$INVITE_URL" ]; then \
				INVITE_URL=$$(echo "$$INVITE_URL" | sed 's|https://teleport-cluster\.teleport-cluster\.svc\.cluster\.local:443|https://localhost:443|g' | sed 's|https://minikube:443|https://localhost:443|g' | sed 's|minikube:443|localhost:443|g'); \
				echo "$$OUTPUT" | sed 's|https://teleport-cluster\.teleport-cluster\.svc\.cluster\.local:443|https://localhost:443|g' | sed 's|https://minikube:443|https://localhost:443|g' | sed 's|minikube:443|localhost:443|g'; \
				echo "$$INVITE_URL" > /tmp/teleport-admin-invite-url.txt; \
			else \
				echo "$$OUTPUT" | sed 's|https://teleport-cluster\.teleport-cluster\.svc\.cluster\.local:443|https://localhost:443|g' | sed 's|https://minikube:443|https://localhost:443|g' | sed 's|minikube:443|localhost:443|g'; \
			fi; \
		fi; \
		echo "✅ Admin user created"; \
	else \
		echo "👤 Admin user already exists, ensuring roles are correct and resetting to get new invite URL..."; \
		kubectl exec -n $$NS $$POD -- tctl users update admin --set-roles=editor,access,k8s-admin 2>/dev/null || true; \
		OUTPUT=$$(kubectl exec -n $$NS $$POD -- tctl users reset admin 2>&1 || echo ""); \
		if [ -n "$$OUTPUT" ]; then \
			INVITE_URL=$$(echo "$$OUTPUT" | grep -oE 'https://[^[:space:]]+/web/invite/[^[:space:]]+' | head -1); \
			if [ -n "$$INVITE_URL" ]; then \
				INVITE_URL=$$(echo "$$INVITE_URL" | sed 's|https://teleport-cluster\.teleport-cluster\.svc\.cluster\.local:443|https://localhost:443|g' | sed 's|https://minikube:443|https://localhost:443|g' | sed 's|minikube:443|localhost:443|g'); \
				echo "$$OUTPUT" | sed 's|https://teleport-cluster\.teleport-cluster\.svc\.cluster\.local:443|https://localhost:443|g' | sed 's|https://minikube:443|https://localhost:443|g' | sed 's|minikube:443|localhost:443|g'; \
				echo "$$INVITE_URL" > /tmp/teleport-admin-invite-url.txt; \
			else \
				echo "$$OUTPUT" | sed 's|https://teleport-cluster\.teleport-cluster\.svc\.cluster\.local:443|https://localhost:443|g' | sed 's|https://minikube:443|https://localhost:443|g' | sed 's|minikube:443|localhost:443|g'; \
			fi; \
		fi; \
		echo "✅ Admin user roles updated and reset"; \
	fi
	@echo ""
	@echo "Step 4/6: Generating Teleport join token..."
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
	TOKEN_OUTPUT=$$(kubectl exec -n $$NS $$POD -- tctl tokens add --type=kube,app,discovery --ttl=24h 2>&1); \
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
	@echo "Step 5/6: Starting Teleport port-forward..."
	@if pgrep -f "kubectl port-forward.*teleport.*443" > /dev/null || pgrep -f "sudo.*kubectl port-forward.*teleport.*443" > /dev/null; then \
		echo "✅ Port-forward already running"; \
	else \
		if kubectl get svc teleport-cluster -n teleport-cluster >/dev/null 2>&1; then \
			echo "⚠️  Port 443 requires sudo privileges."; \
			echo ""; \
			echo "📋 Please run the following command manually in a separate terminal:"; \
			echo "   sudo kubectl port-forward -n teleport-cluster svc/teleport-cluster 443:443"; \
			echo ""; \
			echo "⚠️  Port-forward must be running before accessing Teleport."; \
		elif kubectl get svc teleport -n teleport >/dev/null 2>&1; then \
			echo "⚠️  Port 443 requires sudo privileges."; \
			echo ""; \
			echo "📋 Please run the following command manually in a separate terminal:"; \
			echo "   sudo kubectl port-forward -n teleport svc/teleport 443:443"; \
			echo ""; \
			echo "⚠️  Port-forward must be running before accessing Teleport."; \
		else \
			echo "⚠️  Teleport service not found. Port-forward will need to be started manually."; \
			echo "   Run: sudo kubectl port-forward -n teleport-cluster svc/teleport-cluster 443:443"; \
		fi; \
	fi
	@echo ""
	@echo "Step 6/6: Deploying Dashboard and Teleport Agent..."
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
			CLUSTER=\"minikube\"; \
			echo '⚠️  Using default cluster name: minikube'; \
		fi; \
	fi; \
	K8S_NS=\$$(grep -A 2 '^kubernetes:' config.yaml 2>/dev/null | grep -E '^\s*namespace:' | sed -E 's/.*namespace:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/' | head -1); \
	if [ -z \"\$$K8S_NS\" ]; then \
		K8S_NS=\"kubernetes-dashboard\"; \
	fi; \
	TELEPORT_NS=\$$(grep -A 2 '^teleport:' config.yaml 2>/dev/null | grep -E '^\s*namespace:' | sed -E 's/.*namespace:[[:space:]]*[\"'\'']?([^\"'\'']+)[\"'\'']?.*/\1/' | head -1); \
	if [ -z \"\$$TELEPORT_NS\" ]; then \
		TELEPORT_NS=\"teleport-agent\"; \
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
	if ! kubectl -n \$$K8S_NS get svc kubernetes-dashboard-kong-proxy >/dev/null 2>&1; then \
		echo '❌ kubernetes-dashboard-kong-proxy service not found.'; \
		echo '   Please ensure Kubernetes Dashboard is deployed.'; \
		kubectl -n \$$K8S_NS get svc | grep -i dashboard || echo '   No dashboard services found'; \
		exit 1; \
	fi; \
	DASHBOARD_URI=\"https://kubernetes-dashboard-kong-proxy.\$$K8S_NS.svc.cluster.local\"; \
	echo \"📊 Dashboard URI (internal DNS): \$$DASHBOARD_URI\"; \
	echo '🔧 Adding Teleport annotations for dashboard service...'; \
	kubectl annotate service -n \$$K8S_NS kubernetes-dashboard-kong-proxy \
		\"teleport.dev/name=dashboard\" \
		\"teleport.dev/protocol=https\" \
		\"teleport.dev/ignore-tls=true\" \
		\"teleport.dev/public-addr=dashboard.teleport-cluster.teleport-cluster.svc.cluster.local\" \
		--overwrite 2>/dev/null || echo '⚠️  Failed to add annotations, continuing...'; \
	echo '✅ Added Teleport annotations to dashboard service'; \
	echo '🔧 Installing Teleport Kube Agent...'; \
	TEMP_VALUES=\$$(mktemp); \
	echo \"authToken: \$$TOKEN\" > \$$TEMP_VALUES; \
	echo \"proxyAddr: \$$PROXY\" >> \$$TEMP_VALUES; \
	echo \"kubeClusterName: \$$CLUSTER\" >> \$$TEMP_VALUES; \
	echo 'roles: kube,app,discovery' >> \$$TEMP_VALUES; \
	echo 'insecureSkipProxyTLSVerify: true' >> \$$TEMP_VALUES; \
	echo 'updater:' >> \$$TEMP_VALUES; \
	echo '  enabled: false' >> \$$TEMP_VALUES; \
	echo 'log:' >> \$$TEMP_VALUES; \
	echo '  level: DEBUG' >> \$$TEMP_VALUES; \
	echo 'apps: []' >> \$$TEMP_VALUES; \
	echo 'appResources:' >> \$$TEMP_VALUES; \
	echo '  - labels:' >> \$$TEMP_VALUES; \
	echo '      app.kubernetes.io/name: kong' >> \$$TEMP_VALUES; \
	echo '      app.kubernetes.io/instance: kubernetes-dashboard' >> \$$TEMP_VALUES; \
	echo 'kubernetesDiscovery:' >> \$$TEMP_VALUES; \
	echo '  - types:' >> \$$TEMP_VALUES; \
	echo '    - app' >> \$$TEMP_VALUES; \
	echo '    namespaces:' >> \$$TEMP_VALUES; \
	echo \"    - \$$K8S_NS\" >> \$$TEMP_VALUES; \
	helm upgrade --install teleport-agent teleport/teleport-kube-agent \
		--version 18.6.0 \
		--create-namespace \
		--namespace \$$TELEPORT_NS \
		-f \$$TEMP_VALUES \
		--wait --timeout=5m || true; \
	rm -f \$$TEMP_VALUES"
	@echo ""
	@echo "✅ Full deployment complete!"
	@echo ""
	@echo "============================================================"
	@echo ""
	@echo "📋 Summary:"
	@echo "  ✅ RBAC resources deployed"
	@echo "  ✅ Teleport server deployed and running"
	@echo "  ✅ Admin user created"
	@echo "  ✅ Join token generated"
	@if pgrep -f "kubectl port-forward.*teleport.*443" > /dev/null || pgrep -f "sudo.*kubectl port-forward.*teleport.*443" > /dev/null; then \
		echo "  ✅ Port-forward active (https://localhost:443)"; \
	else \
		echo "  ⚠️  Port-forward NOT running (required for access)"; \
	fi
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
		if ! pgrep -f "kubectl port-forward.*teleport.*443" > /dev/null && ! pgrep -f "sudo.*kubectl port-forward.*teleport.*443" > /dev/null; then \
			echo "  0️⃣  Start Port-Forward (REQUIRED):"; \
			echo "     • Run in a separate terminal:"; \
			if kubectl get svc teleport-cluster -n teleport-cluster >/dev/null 2>&1; then \
				echo "       sudo kubectl port-forward -n teleport-cluster svc/teleport-cluster 443:443"; \
			else \
				echo "       sudo kubectl port-forward -n teleport svc/teleport 443:443"; \
			fi; \
			echo "     • Keep this terminal open while using Teleport"; \
			echo ""; \
		fi; \
		echo "  1️⃣  Accept the Admin Invite:"; \
		echo "     • Open the URL above in your browser"; \
		echo "     • Set your admin password"; \
		echo ""; \
		echo "  2️⃣  Access Teleport Web Console:"; \
		echo "     • URL: https://localhost:443"; \
		echo "     • Log in with username: admin"; \
		echo ""; \
		echo "  3️⃣  Get Dashboard Access Tokens:"; \
		echo "     • Run: make get-tokens"; \
		echo "     • Copy the admin token for dashboard login"; \
		echo ""; \
		echo "  4️⃣  Access Kubernetes Dashboard via Teleport:"; \
		echo "     • In Teleport Web UI, go to: Applications → kube-dashboard"; \
		echo "     • Paste the token from step 3 when prompted"; \
		echo ""; \
		echo "  5️⃣  View Logs (if needed):"; \
		echo "     • Run: make logs"; \
	else \
		echo "📋 Next Steps:"; \
		echo ""; \
		if ! pgrep -f "kubectl port-forward.*teleport.*443" > /dev/null && ! pgrep -f "sudo.*kubectl port-forward.*teleport.*443" > /dev/null; then \
			echo "  0️⃣  Start Port-Forward (REQUIRED):"; \
			echo "     • Run in a separate terminal:"; \
			if kubectl get svc teleport-cluster -n teleport-cluster >/dev/null 2>&1; then \
				echo "       sudo kubectl port-forward -n teleport-cluster svc/teleport-cluster 443:443"; \
			else \
				echo "       sudo kubectl port-forward -n teleport svc/teleport 443:443"; \
			fi; \
			echo "     • Keep this terminal open while using Teleport"; \
			echo ""; \
		fi; \
		echo "  1️⃣  Access Teleport Web Console:"; \
		echo "     • URL: https://localhost:443"; \
		echo ""; \
		echo "  2️⃣  Get Dashboard Access Tokens:"; \
		echo "     • Run: make get-tokens"; \
		echo "     • Copy the admin token for dashboard login"; \
		echo ""; \
		echo "  3️⃣  Access Kubernetes Dashboard via Teleport:"; \
		echo "     • In Teleport Web UI, go to: Applications → kube-dashboard"; \
		echo "     • Paste the token from step 2 when prompted"; \
		echo ""; \
		echo "  4️⃣  View Logs (if needed):"; \
		echo "     • Run: make logs"; \
	fi
	@echo ""
	@echo "============================================================"
	@echo ""

# Clean up all deployments (Teleport server, Dashboard, Agent, port-forwards, RBAC)
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
	pkill -f "kubectl port-forward.*teleport.*443" 2>/dev/null || true; \
	pkill -f "sudo.*kubectl port-forward.*teleport.*443" 2>/dev/null || true; \
	echo "✅ Port-forward cleanup complete"
	@echo ""
	@echo "Step 2/6: Uninstalling Helm releases..."
	@K8S_NS=$$(grep -A 2 "^kubernetes:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E 's/.*namespace:[[:space:]]*["'\'']?([^"'\'']+)["'\'']?.*/\1/' | head -1); \
	if [ -z "$$K8S_NS" ]; then \
		K8S_NS="kubernetes-dashboard"; \
	fi; \
	TELEPORT_NS=$$(grep -A 2 "^teleport:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E 's/.*namespace:[[:space:]]*["'\'']?([^"'\'']+)["'\'']?.*/\1/' | head -1); \
	if [ -z "$$TELEPORT_NS" ]; then \
		TELEPORT_NS="teleport-agent"; \
	fi; \
	echo "🗑️  Uninstalling Teleport Agent from namespace: $$TELEPORT_NS"; \
	helm uninstall teleport-agent --namespace $$TELEPORT_NS 2>/dev/null || true; \
	echo "🗑️  Uninstalling Kubernetes Dashboard from namespace: $$K8S_NS"; \
	helm uninstall kubernetes-dashboard --namespace $$K8S_NS 2>/dev/null || true; \
	echo "🗑️  Uninstalling Teleport Cluster from namespace: teleport-cluster"; \
	helm uninstall teleport-cluster --namespace teleport-cluster 2>/dev/null || true; \
	echo "✅ Helm releases uninstalled"
	@echo ""
	@echo "Step 3/6: Cleaning up remaining Teleport Kube Agent resources..."
	@TELEPORT_NS=$$(grep -A 2 "^teleport:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E 's/.*namespace:[[:space:]]*["'\'']?([^"'\'']+)["'\'']?.*/\1/' | head -1); \
	if [ -z "$$TELEPORT_NS" ]; then \
		TELEPORT_NS="teleport-agent"; \
	fi; \
	kubectl delete pod -n $$TELEPORT_NS -l app.kubernetes.io/name=teleport-kube-agent --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete pod -n $$TELEPORT_NS -l app=teleport-kube-agent --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete statefulset -n $$TELEPORT_NS teleport-agent --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete statefulset -n $$TELEPORT_NS teleport-kube-agent --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete secret -n $$TELEPORT_NS -l app.kubernetes.io/name=teleport-kube-agent --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete secret -n $$TELEPORT_NS teleport-agent-join-token --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete secret -n $$TELEPORT_NS teleport-kube-agent-join-token --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete secret -n $$TELEPORT_NS teleport-agent-0-state --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete secret -n $$TELEPORT_NS teleport-kube-agent-0-state --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete secret -n $$TELEPORT_NS -l 'app.kubernetes.io/instance=teleport-agent' --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete secret -n $$TELEPORT_NS -l 'app.kubernetes.io/instance=teleport-kube-agent' --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete configmap -n $$TELEPORT_NS teleport-agent --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete configmap -n $$TELEPORT_NS teleport-kube-agent --ignore-not-found=true 2>/dev/null || true; \
	kubectl delete configmap -n $$TELEPORT_NS -l app.kubernetes.io/name=teleport-kube-agent --ignore-not-found=true 2>/dev/null || true; \
	echo "✅ Teleport Kube Agent resources cleaned up"
	@echo ""
	@echo "Step 4/6: Removing Teleport server..."
	@helm uninstall teleport-cluster --namespace teleport-cluster 2>/dev/null || true
	@echo "✅ Teleport server removed"
	@echo ""
	@echo "Step 5/6: Deleting namespaces..."
	@K8S_NS=$$(grep -A 2 "^kubernetes:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E 's/.*namespace:[[:space:]]*["'\'']?([^"'\'']+)["'\'']?.*/\1/' | head -1); \
	if [ -z "$$K8S_NS" ]; then \
		K8S_NS="kubernetes-dashboard"; \
	fi; \
	TELEPORT_NS=$$(grep -A 2 "^teleport:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E 's/.*namespace:[[:space:]]*["'\'']?([^"'\'']+)["'\'']?.*/\1/' | head -1); \
	if [ -z "$$TELEPORT_NS" ]; then \
		TELEPORT_NS="teleport-agent"; \
	fi; \
	echo "🗑️  Deleting namespace: $$TELEPORT_NS"; \
	kubectl delete namespace $$TELEPORT_NS 2>/dev/null || true; \
	echo "🗑️  Deleting namespace: $$K8S_NS"; \
	kubectl delete namespace $$K8S_NS 2>/dev/null || true; \
	echo "🗑️  Deleting namespace: teleport-agent"; \
	kubectl delete namespace teleport-agent 2>/dev/null || true; \
	echo "🗑️  Deleting namespace: teleport"; \
	kubectl delete namespace teleport 2>/dev/null || true; \
	echo "✅ Namespaces deleted"
	@echo ""
	@echo "Step 6/6: Removing RBAC resources..."
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
		TELEPORT_NS="teleport-agent"; \
	fi; \
	echo ""; \
	echo "Kubernetes Dashboard (namespace: $$K8S_NS):"; \
	helm status kubernetes-dashboard --namespace $$K8S_NS 2>/dev/null || echo "  Not installed"; \
	echo ""; \
	echo "Teleport Agent (namespace: $$TELEPORT_NS):"; \
	helm status teleport-agent --namespace $$TELEPORT_NS 2>/dev/null || echo "  Not installed"

# Get dashboard access tokens
get-tokens:
	@echo "🔑 Dashboard Access Tokens:"
	@echo ""
	@K8S_NS=$$(grep -A 2 "^kubernetes:" config.yaml 2>/dev/null | grep -E "^\s*namespace:" | sed -E 's/.*namespace:[[:space:]]*["'\'']?([^"'\'']+)["'\'']?.*/\1/' | head -1); \
	if [ -z "$$K8S_NS" ]; then \
		K8S_NS="kubernetes-dashboard"; \
	fi; \
	echo "📋 Using namespace: $$K8S_NS"; \
	echo ""; \
	echo "Admin Token (for dashboard login):"; \
	TOKEN=$$(kubectl get secret dashboard-token -n $$K8S_NS -o jsonpath="{.data.token}" 2>/dev/null | base64 -d 2>/dev/null || echo ""); \
	if [ -n "$$TOKEN" ]; then \
		echo "$$TOKEN"; \
		echo ""; \
		echo "✅ Copy the token above and paste it into the dashboard login page"; \
	else \
		echo "  ⚠️  Secret 'dashboard-token' not found. Waiting for token generation..."; \
		echo "  💡 Run 'make deploy-rbac' to create the Secret, then wait a few seconds"; \
	fi; \
	echo ""; \
	echo "Read-only Token:"; \
	READONLY_TOKEN=$$(kubectl get secret dashboard-readonly-token -n $$K8S_NS -o jsonpath="{.data.token}" 2>/dev/null | base64 -d 2>/dev/null || echo ""); \
	if [ -n "$$READONLY_TOKEN" ]; then \
		echo "$$READONLY_TOKEN"; \
	else \
		echo "  ⚠️  Secret 'dashboard-readonly-token' not found"; \
	fi; \
	echo ""

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
# Show Teleport agent logs (follow mode by default)
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
				TELEPORT_NS="teleport-agent"; \
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
				TELEPORT_NS="teleport-agent"; \
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
