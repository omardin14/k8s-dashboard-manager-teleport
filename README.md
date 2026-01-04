# Kubernetes Dashboard Manager with Teleport

A complete Kubernetes solution that deploys the Kubernetes Dashboard and makes it accessible via Teleport Application Access with both admin and readonly access roles.

![Status](https://img.shields.io/badge/status-sandbox-yellow)
![License](https://img.shields.io/badge/license-MIT-blue)

> ⚠️ **Note:** This setup is designed for local development/testing only. See the [Security](#-security) section for important security considerations.

## 📑 Table of Contents

- [Quick Start](#-quick-start)
- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Architecture](#-architecture)
- [Deployment](#-deployment)
- [Accessing the Dashboard](#-accessing-the-dashboard)
- [Configuration](#-configuration)
- [Security](#-security)
- [Troubleshooting](#-troubleshooting)
- [Cleanup](#-cleanup)
- [References](#-references)

---

## 🚀 Quick Start

### Deployment Modes

The setup supports two deployment modes based on `proxy_addr` in `config.yaml`:

1. **Local Mode** (`proxy_addr: ""`): Deploys Teleport cluster in Kubernetes (Minikube)
2. **Enterprise Mode** (`proxy_addr: "your-proxy.teleport.com:443"`): Connects to existing Teleport Enterprise/Cloud

### Prerequisites

**For Local Mode:**
- **Minikube** installed and running
- `kubectl` configured to access your cluster
- `helm` installed (v3.x)
- **macOS/Linux** (for `/etc/hosts` modification)
- DNS mappings in `/etc/hosts` (automatically checked)

**For Enterprise Mode:**
- `kubectl` configured to access your cluster
- `helm` installed (v3.x)
- Teleport Enterprise/Cloud instance
- Join token from Teleport (must be set in `config.yaml`)

### Fastest Deployment (Automated - Recommended)

**1. Create config file:**
```bash
make config
```

**2. Configure deployment mode:**

**For Local Mode (default):**
```yaml
teleport:
  proxy_addr: ""  # Empty = local mode
  cluster_name: "minikube"
  cluster_namespace: "teleport-cluster"
  agent_namespace: "teleport-agent"
```

**For Enterprise Mode:**
```yaml
teleport:
  proxy_addr: "your-proxy.teleport.com:443"  # Set = Enterprise mode
  cluster_name: "your-cluster-name"
  cluster_namespace: "teleport-cluster"  # Not used in Enterprise mode
  agent_namespace: "teleport-agent"
```

**Note:** For Enterprise Mode, the join token is auto-generated via `tctl` if it's installed and configured. If `tctl` is not found, it will be automatically installed. You must authenticate to your Teleport Enterprise cluster first using:
```bash
tsh login --user=YOUR_USER --proxy=your-proxy.teleport.com:443 --auth local
```
⚠️ **MFA WARNING**: Use an authenticator app (TOTP) for MFA, not passkeys. Passkeys stored in web browsers are not accessible to `tsh` and can cause authentication issues. See: https://github.com/gravitational/teleport/issues/44600

**3. Deploy:**
```bash
# For local mode, setup minikube first
make setup-minikube

# Deploy everything
make helm-deploy
```

**What `make helm-deploy` does:**

**Local Mode (5 steps):**
1. ✅ Checks prerequisites (minikube addons, DNS mappings)
2. ✅ Deploys RBAC resources
3. ✅ Deploys Teleport server to Kubernetes
4. ✅ Creates admin user with Kubernetes access
5. ✅ Generates join token automatically
6. ✅ Deploys Kubernetes Dashboard and Teleport agent with discovery enabled

**Enterprise Mode (4 steps):**
1. ✅ Deploys RBAC resources
2. ✅ Sets up tctl (auto-installs `tctl` if needed)
3. ✅ Generates join token via `tctl`
4. ✅ Deploys Kubernetes Dashboard and Teleport agent with static app configuration (no discovery)

**Next steps:**
- **Local Mode**: Access Teleport Web UI at `https://teleport-cluster.teleport-cluster.svc.cluster.local:8080` (port-forward started automatically)
- **Enterprise Mode**: Access your Teleport Enterprise/Cloud instance
- Get dashboard tokens: `make get-tokens`
- Access dashboard via Teleport: Applications → `dashboard` (Local Mode) or `kube-dashboard` (Enterprise Mode)

**To clean up everything:**
```bash
make helm-clean
```

---

## ✨ Features

### 📊 Kubernetes Dashboard
- Deploys official Kubernetes Dashboard via Helm
- Latest stable version with all features
- Secure ClusterIP service (not exposed publicly)
- Automatic discovery via Teleport

### 🔐 Teleport Application Access
- **Admin Access**: Full cluster-admin permissions via `dashboard` app
- Secure access through Teleport proxy
- No need to expose dashboard publicly
- Single sign-on through Teleport
- Automatic service discovery

### 🛡️ Security (Sandbox Only)
- Two separate service accounts (admin and readonly)
- Proper RBAC with ClusterRole and ClusterRoleBinding
- Long-lived bearer tokens for dashboard authentication
- Teleport handles all authentication and authorization
- Dashboard only accessible via Teleport

---

## 📋 Prerequisites

### Required (All Modes)
- `kubectl`: Configured to access your cluster
- `helm`: Version 3.x installed
- `python3`: Python 3.7+ installed
- `pyyaml`: Python YAML library (installed via `pip install -r src/requirements.txt`)

### Local Mode Only
- **Minikube**: Installed and running
- **macOS/Linux**: For `/etc/hosts` modification
- **Minikube Addons**: Automatically enabled by the setup:
  - `ingress` addon
  - `ingress-dns` addon
- **DNS Mappings**: Required in `/etc/hosts` (checked automatically):
  ```
  127.0.0.1 teleport-cluster.teleport-cluster.svc.cluster.local
  127.0.0.1 dashboard.teleport-cluster.teleport-cluster.svc.cluster.local
  ```
  The `make helm-deploy` command will check for these and fail if they're missing.

### Enterprise Mode Only
- **Teleport Enterprise/Cloud**: Existing instance accessible
- **Authentication**: Must authenticate to Teleport Enterprise cluster before deployment:
  ```bash
  tsh login --user=YOUR_USER --proxy=your-proxy.teleport.com:443 --auth local
  ```
  ⚠️ **MFA WARNING**: Use an authenticator app (TOTP) for MFA, not passkeys. See: https://github.com/gravitational/teleport/issues/44600
- **Join Token**: Auto-generated via `tctl` (auto-installed if not found)

---

## 🏗️ Architecture

### Project Structure

The project uses a Python-based deployment system with modular components:

```
src/
├── main.py              # Single entry point for all commands (deploy, clean, utils)
├── requirements.txt     # Python dependencies
├── deploy/              # Deployment module
│   ├── __init__.py      # Orchestrates local/enterprise deployment
│   ├── common.py        # Shared functions (RBAC, Dashboard, Agent, StepCounter)
│   ├── local.py         # Local mode specific functions
│   └── enterprise.py    # Enterprise mode specific functions
├── utils/               # Utility functions
│   └── __init__.py      # Token retrieval, status, logs, etc.
└── clean/               # Cleanup functions
    └── __init__.py      # Cleanup operations
```

**Commands available via `main.py`:**
- `deploy` (or no args) - Deploy Teleport, Dashboard, and Agent
- `clean` - Clean up all deployed resources
- `get-tokens` - Get dashboard access tokens
- `get-clusterip` - Get dashboard ClusterIP
- `status` - Show overall status
- `helm-status` - Show Helm deployment status
- `logs` - Interactive menu to view logs

### Deployment Components

The solution consists of:

1. **Teleport Cluster** (Local Mode Only): 
   - Deployed via official Helm chart
   - Runs in `teleport-cluster` namespace
   - Web UI on port 8080 (via port-forward)
   - Self-signed certificates for local testing

2. **Kubernetes Dashboard**: 
   - Deployed via official Helm chart
   - Runs in `kubernetes-dashboard` namespace
   - Exposed via ClusterIP service (internal only)
   - Automatically discovered by Teleport via discovery service (Local Mode)

3. **Teleport Kube Agent**:
   - Deployed via Teleport Helm chart
   - Runs in `teleport-agent` namespace
   - Registers Kubernetes cluster with Teleport
   - **Local Mode**: Discovers and registers dashboard application via discovery service
     - Roles: `kube,app,discovery`
     - Filters discovery by namespace (only discovers services in `kubernetes-dashboard` namespace)
   - **Enterprise Mode**: Uses static app configuration
     - Roles: `kube,app` (no discovery)
     - Static app pointing to `kubernetes-dashboard-kong-proxy` ClusterIP
     - `insecure_skip_verify: true` for self-signed certificates

4. **RBAC Resources**:
   - `dashboard-admin-account`: ServiceAccount with cluster-admin role
   - `dashboard-readonly-account`: ServiceAccount with readonly ClusterRole
   - Tokens stored in Kubernetes Secrets

```
┌─────────────────────────────────────────┐
│  Kubernetes Cluster (Minikube)          │
│  ┌───────────────────────────────────┐  │
│  │  Teleport Cluster                 │  │
│  │  - Auth Service                   │  │
│  │  - Proxy Service (443)              │  │
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │  Kubernetes Dashboard             │  │
│  │  (ClusterIP Service)               │  │
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │  Teleport Kube Agent              │  │
│  │  - Registers cluster              │  │
│  │  - Discovers applications         │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
           │
           │ Port Forward (443:443) - Local Mode Only
           │
┌─────────────────────────────────────────┐
│  User Browser                            │
│  - Teleport Web UI                       │
│  - Dashboard Access                      │
└─────────────────────────────────────────┘
```

---

## 📦 Deployment

### Installation

Python dependencies are automatically installed when you run any Makefile command. The Makefile will:
1. Check if a virtual environment (`venv`) exists
2. If not, automatically create it and install dependencies
3. Use the virtual environment for all Python commands

**Manual installation (optional):**
```bash
make install
```

This creates a virtual environment and installs dependencies from `src/requirements.txt`.

### Configuration Setup

The setup supports two deployment modes based on `proxy_addr` in `config.yaml`:

```bash
# Create config file
make config
```

#### Local Mode Configuration

For local testing with Minikube (deploys Teleport cluster):

```yaml
teleport:
  proxy_addr: ""  # Empty = local mode
  cluster_name: "minikube"
  cluster_namespace: "teleport-cluster"
  agent_namespace: "teleport-agent"

kubernetes:
  namespace: "kubernetes-dashboard"
```

**What happens:**
- Teleport cluster is deployed to Kubernetes
- Admin user is created automatically
- Join token is generated automatically
- Prerequisites are checked (minikube addons, DNS mappings)

#### Enterprise Mode Configuration

For connecting to existing Teleport Enterprise/Cloud:

```yaml
teleport:
  proxy_addr: "your-proxy.teleport.com:443"  # Set = Enterprise mode
  cluster_name: "your-cluster-name"
  cluster_namespace: "teleport-cluster"  # Not used in Enterprise mode
  agent_namespace: "teleport-agent"

kubernetes:
  namespace: "kubernetes-dashboard"
```

**What happens:**
- Teleport cluster is NOT deployed (uses existing)
- `tctl` is auto-installed if not found
- `tctl` is configured to use proxy from `config.yaml`
- Join token is auto-generated via `tctl` (requires authentication first)
- Agent uses static app configuration (no discovery)
- Prerequisites check is skipped (no minikube/DNS requirements)

### Automated Deployment

The deployment is handled by a single Python entry point (`src/main.py`) called via Makefile targets:

```bash
# Deploy everything
make helm-deploy
```

This runs `python3 src/main.py deploy`, which orchestrates the deployment using the modular Python structure:
- **`src/main.py`**: Single entry point for all commands (deploy, clean, utilities)
- **`src/deploy/common.py`**: Shared deployment functions (RBAC, Dashboard, Agent common parts, StepCounter)
- **`src/deploy/local.py`**: Local mode specific functions (Teleport cluster, admin user, token generation)
- **`src/deploy/enterprise.py`**: Enterprise mode specific functions (tctl setup, token generation)

**Note:** Step numbers are dynamically calculated based on the deployment mode:
- **Local Mode**: Shows "Step X/5" (5 total steps)
- **Enterprise Mode**: Shows "Step X/4" (4 total steps)

**Local Mode Steps (5 total):**
1. **Step 1/5**: Deploy RBAC resources - `deploy/common.py`
2. **Step 2/5**: Deploy Teleport cluster - `deploy/local.py`
   - `clusterName: minikube`
   - `proxyListenerMode: multiplex`
   - `publicAddr: teleport-cluster.teleport-cluster.svc.cluster.local:8080`
   - `tunnelPublicAddr: teleport-cluster.teleport-cluster.svc.cluster.local:443`
3. **Step 3/5**: Create admin user with `k8s-admin` role - `deploy/local.py`
4. **Step 4/5**: Generate join token with `kube,app,discovery` roles - `deploy/local.py`
5. **Step 5/5**: Deploy Kubernetes Dashboard and Teleport Kube Agent - `deploy/common.py`
   - Dashboard deployment
   - Agent with `roles: kube,app,discovery`
   - Discovery configuration (filters by namespace)
   - Patch service and start port-forward - `deploy/local.py`

**Enterprise Mode Steps (4 total):**
1. **Step 1/4**: Deploy RBAC resources - `deploy/common.py`
2. **Step 2/4**: Setup tctl - `deploy/enterprise.py`
   - Auto-installs `tctl` if not found
   - Configures `tctl` to use proxy from `config.yaml`
   - Requires authentication: `tsh login --user=YOUR_USER --proxy=PROXY --auth local`
3. **Step 3/4**: Generate join token - `deploy/enterprise.py`
   - Generates token with `kube,app` roles (no discovery)
4. **Step 4/4**: Deploy Kubernetes Dashboard and Teleport Kube Agent - `deploy/common.py`
   - Dashboard deployment
   - Agent with `roles: kube,app` (static configuration, no discovery)
   - Static app configuration pointing to `kubernetes-dashboard-kong-proxy` ClusterIP
   - `insecure_skip_verify: true` for self-signed certificates

**Note:** 
- Teleport cluster deployment (Local Mode, Step 2/5) may take up to 5 minutes while the Helm chart deploys and pods become ready.
- Step numbers are dynamically calculated and displayed correctly for each mode (Local: 5 steps, Enterprise: 4 steps).
- All Python commands automatically install dependencies in a virtual environment if needed.

---

## 🔑 Accessing the Dashboard

### Step 1: Get Dashboard Tokens

```bash
make get-tokens
```

This runs `python3 src/main.py get-tokens` and displays:
- **Admin Token**: For full cluster access
- **Readonly Token**: For read-only access

### Step 2: Access via Teleport

**For Local Mode:**
1. **Access Teleport Web UI**
   - URL: `https://teleport-cluster.teleport-cluster.svc.cluster.local:8080` (via port-forward)
   - Accept the self-signed certificate warning (expected for local testing)
   - Port-forward is automatically started by `make helm-deploy`

2. **Accept Admin Invite**
   - Use the invite URL shown in the deployment summary
   - Set your admin password

3. **Navigate to Applications**
   - Click on **Applications** in the sidebar
   - You should see the `dashboard` application (discovered automatically via discovery service)

4. **Open Dashboard**
   - Click on the `dashboard` application
   - Teleport will open the dashboard in a new window/tab

**For Enterprise Mode:**
1. **Access Teleport Web UI**
   - Use your Teleport Enterprise/Cloud URL (from `config.yaml`)
   - Log in with your existing credentials

2. **Navigate to Applications**
   - Click on **Applications** in the sidebar
   - You should see the `kube-dashboard` application (configured statically)

3. **Open Dashboard**
   - Click on the `kube-dashboard` application
   - Teleport will open the dashboard in a new window/tab

5. **Authenticate with Dashboard**
   - When prompted for a token, paste the appropriate token:
     - Use **admin token** for full access
     - Use **readonly token** for read-only access
   - Click **Sign In**

6. **Use the Dashboard**
   - You now have access to the Kubernetes Dashboard
   - Admin access allows full cluster management
   - Readonly access allows viewing resources only

---

## ⚙️ Configuration

### Teleport Cluster Configuration

The Teleport cluster is configured with these values:

```yaml
clusterName: minikube
proxyListenerMode: multiplex
acme: false
publicAddr:
  - teleport-cluster.teleport-cluster.svc.cluster.local:443
auth:
  service:
    enabled: true
    type: ClusterIP
```

### Teleport Kube Agent Configuration

**Local Mode:**
```yaml
roles: kube,app,discovery
updater:
  enabled: false
kubernetesDiscovery:
  - types:
    - app
    namespaces:
    - kubernetes-dashboard
```

**Enterprise Mode:**
```yaml
roles: kube,app
updater:
  enabled: false
apps:
  - name: kube-dashboard
    uri: https://{CLUSTER_IP}
    insecure_skip_verify: true
    labels:
      cluster: {CLUSTER_NAME}
```

**Note:** 
- **Local Mode**: The dashboard service is automatically discovered by Teleport's discovery service. No manual annotations or service patching is required.
- **Enterprise Mode**: Uses static app configuration pointing directly to the `kubernetes-dashboard-kong-proxy` service ClusterIP. Discovery is disabled.

---

## 🔒 Security

### ⚠️ Security Risk Assessment

**Current Status:** 🔴 **CRITICAL RISK (Not Production Ready)**
**Scope:** Local Minikube development environment only.

This architecture deliberately bypasses standard security controls (TLS validation, DNS resolution, HA storage) to function within a single-node, air-gapped local environment. Deploying this configuration to a shared or public network exposes the infrastructure to Man-in-the-Middle (MitM) attacks, data loss, and denial of service.

#### 1. Network & Transport Security

**🔴 Risk: Broken Trust Chain (MitM Vulnerability)**

**Configuration:**
- `insecureSkipProxyTLSVerify: true` (Agent side)
- `--insecure` (Cluster side)
- `teleport.dev/ignore-tls: true` (Dashboard annotation)

**Impact:**
The Teleport components (Agent, Proxy, Auth) are configured to blindly trust any server presenting a certificate, regardless of validity.

- **Attack Vector:** An attacker on the local network (e.g., public WiFi) could intercept traffic between the Agent and the Cluster. The Agent would accept the attacker's fake certificate and hand over session credentials.
- **Production Requirement:** Valid x.509 certificates (Let's Encrypt/ACME) or a properly distributed internal PKI. All "insecure" flags must be removed.

**🔴 Risk: Ephemeral Connection Tunneling**

**Configuration:**
- Access relies on `kubectl port-forward` tunnels.
- `/etc/hosts` DNS spoofing (`127.0.0.1 teleport-cluster...`).

**Impact:**
- **Availability:** Port forwarding is a debug tool. It is single-threaded and drops connections upon network jitter or timeout.
- **Scalability:** Requires every user to have root access to their local machine to modify `/etc/hosts` and active Kubernetes credentials to open tunnels.
- **Production Requirement:** A dedicated Layer 4 (TCP) Load Balancer (AWS NLB, GCP LB) with a public, resolvable DNS record (e.g., `teleport.example.com`).

#### 2. Data Integrity & Availability

**🔴 Risk: Single Point of Failure (SPOF)**

**Configuration:**
- Single replica deployment (no high availability configured)
- `proxyListenerMode: multiplex` (Single pod handling all roles)

**Impact:**
If the single Teleport pod crashes (OOM, node update, storage failure), the entire access gateway goes offline.

- **Consequence:** Immediate lockout. No SSH, Kubernetes, or Application access is possible until the specific pod recovers.
- **Production Requirement:** Minimum 2 replicas spread across availability zones (`topologySpreadConstraints`) with `podDisruptionBudget` enabled.

**🔴 Risk: Volatile Audit & Session Data**

**Configuration:**
- Storage uses local Kubernetes `PersistentVolumeClaim` (PVC) on the Minikube node.

**Impact:**
- **Data Loss:** If the Minikube virtual machine is deleted or the disk corrupts, **all** audit logs and session recordings are permanently lost.
- **Compliance Violation:** Fails SOC2/ISO27001 requirements for durable, immutable audit trails.
- **Production Requirement:**
  - **Cluster State:** DynamoDB (AWS), Firestore (GCP), or etcd.
  - **Audit/Sessions:** S3 (AWS) or GCS (GCP) with Object Lock enabled.

#### 3. Access Control & Identity

**🟠 Risk: Static & Long-Lived Tokens**

**Configuration:**
- Manual token generation: `tctl tokens add --type=kube,app,discovery --ttl=1h`.
- Tokens are often hardcoded into Helm `values.yaml` or shell history during setup.

**Impact:**
If a static token leaks, an attacker can register a malicious node to the cluster and potentially pivot laterally.

- **Production Requirement:** Use short-lived dynamic joining methods:
  - **AWS:** IAM Joining (Node Identity).
  - **Kubernetes:** Token Review API / Teleport Operator.

**🟠 Risk: Local Development Configuration**

**Configuration:**
- Single port configuration (443) for all traffic
- Local DNS mappings via `/etc/hosts`
- Self-signed certificates for local testing

**Impact:**
- **Portability:** Configuration is specific to local development environment
- **Production Requirement:** Use proper DNS resolution and valid certificates (Let's Encrypt/ACME) for production deployments

#### 4. Remediation Plan (Path to Production)

To move from **Sandbox** to **Production**, the following refactoring is mandatory:

1. **Switch Storage Backend:**
   - Update `teleport.yaml` to use AWS DynamoDB + S3 (or equivalent cloud services) instead of local PVCs.

2. **Enable ACME / TLS:**
   - Set `acme: true` and `acmeEmail: your-email@domain.com` in Helm.
   - Remove all `--insecure` flags.

3. **Implement Ingress/LoadBalancer:**
   - Provision a Cloud Load Balancer listening on 443.
   - Create a public DNS `A` record pointing to the LB.

4. **Scale Up:**
   - Set `highAvailability.replicaCount: 2` (or 3).
   - Enable `podDisruptionBudget`.

5. **Remove Local Hacks:**
   - Delete `/etc/hosts` entries.
   - Stop `kubectl port-forward`.

### RBAC Configuration

**Admin Access:**
- ServiceAccount: `dashboard-admin-account`
- Role: `cluster-admin` (full cluster access)
- Token: Stored in `dashboard-token` secret

**Readonly Access:**
- ServiceAccount: `dashboard-readonly-account`
- Role: Custom `dashboard-readonly-role` with:
  - `get`, `list`, `watch` on all resources
  - No create, update, delete, or patch permissions
- Token: Stored in `dashboard-readonly-token` secret

### Teleport Roles

**k8s-admin Role:**
- `kubernetes_labels: {"*": "*"}`
- `kubernetes_groups: ["system:masters"]`
- Assigned to admin user for Kubernetes access

---

## 🐛 Troubleshooting

### Port-Forward Not Starting

**Issue**: Port-forward fails to start

**Solutions:**
1. Check if port 8080 is already in use (Local Mode):
   ```bash
   lsof -i :8080
   ```

2. Check if the service has port 8080:
   ```bash
   kubectl get svc -n teleport-cluster teleport-cluster -o yaml | grep -A 5 ports
   ```

3. For Local Mode, manually start port-forward:
   ```bash
   kubectl port-forward -n teleport-cluster svc/teleport-cluster 8080:8080
   ```

4. Check port-forward logs:
   ```bash
   cat /tmp/teleport-port-forward.log
   ```

### Dashboard Not Appearing in Teleport

**Issue**: Applications don't show up in Teleport web UI

**Solutions:**
1. Check Teleport agent logs:
   ```bash
   kubectl logs -n teleport-agent -l app.kubernetes.io/name=teleport-kube-agent
   ```

2. Verify discovery is enabled and filtering correctly:
   ```bash
   kubectl get pods -n teleport-agent -l app.kubernetes.io/name=teleport-kube-agent
   kubectl get svc -n kubernetes-dashboard
   ```

3. Check if dashboard service exists:
   ```bash
   kubectl get svc -n kubernetes-dashboard kubernetes-dashboard-kong-proxy
   ```

### Cannot Access Teleport Web UI (Local Mode)

**Issue**: Can't access `https://teleport-cluster.teleport-cluster.svc.cluster.local:8080`

**Solutions:**
1. Check if port-forward is running:
   ```bash
   pgrep -f "kubectl port-forward.*teleport.*8080"
   ```

2. Check `/etc/hosts` has the DNS mapping:
   ```bash
   grep teleport-cluster /etc/hosts
   ```

3. Check Teleport pods are running:
   ```bash
   kubectl get pods -n teleport-cluster
   ```

4. Manually start port-forward if needed:
   ```bash
   kubectl port-forward -n teleport-cluster svc/teleport-cluster 8080:8080
   ```

5. For Enterprise Mode, verify your proxy address is correct in `config.yaml`

### Teleport Agent Not Starting

**Issue**: Teleport agent pod is in CrashLoopBackOff

**Solutions:**
1. Check pod logs:
   ```bash
   kubectl logs -n teleport-agent -l app.kubernetes.io/name=teleport-kube-agent
   ```

2. Verify authentication and token generation (Enterprise Mode):
   ```bash
   # Check if authenticated
   tctl status
   
   # If not authenticated, login first
   tsh login --user=YOUR_USER --proxy=your-proxy.teleport.com:443 --auth local
   ```

3. Check if proxy address is reachable:
   ```bash
   # For Enterprise Mode, verify proxy address
   grep proxy_addr config.yaml
   ```

### Prerequisites Check Failing

**Issue**: `make helm-deploy` fails on prerequisites

**Solutions:**
1. Enable minikube addons manually:
   ```bash
   minikube addons enable ingress
   minikube addons enable ingress-dns
   ```

2. Add DNS mappings to `/etc/hosts`:
   ```bash
   sudo sh -c 'echo "127.0.0.1 teleport-cluster.teleport-cluster.svc.cluster.local" >> /etc/hosts'
   sudo sh -c 'echo "127.0.0.1 dashboard.teleport-cluster.teleport-cluster.svc.cluster.local" >> /etc/hosts'
   ```

---

## 🧹 Cleanup

### Remove All Resources

```bash
make helm-clean
```

This runs `python3 src/main.py clean`, which orchestrates cleanup using `src/clean/__init__.py`:

- Stop port-forward (if running)
- Uninstall Teleport Kube Agent
- Uninstall Kubernetes Dashboard
- Uninstall Teleport Cluster (Local Mode only)
- Remove namespaces
- Clean up RBAC resources

### Available Make Commands

The Makefile provides convenient wrappers around the single Python entry point:

**Deployment:**
- `make helm-deploy` → `python3 src/main.py deploy` (or `python3 src/main.py` - deploy is default)
- `make helm-clean` → `python3 src/main.py clean`
- `make helm-status` → `python3 src/main.py helm-status`

**Utilities:**
- `make get-tokens` → `python3 src/main.py get-tokens`
- `make get-clusterip` → `python3 src/main.py get-clusterip`
- `make status` → `python3 src/main.py status`
- `make logs` → `python3 src/main.py logs`

**Note:** All commands automatically check for and create a virtual environment (`venv`) if it doesn't exist, ensuring dependencies are installed before execution.

**Minikube Management (Shell-based):**
- `make config` - Create config.yaml from example
- `make setup-minikube` - Set up minikube cluster
- `make check-minikube` - Check minikube installation
- `make start-minikube` - Start minikube
- `make stop-minikube` - Stop minikube
- `make reset-minikube` - Reset minikube cluster

### Manual Cleanup

```bash
# Stop port-forward (Local Mode)
pkill -f "kubectl port-forward.*teleport.*8080"

# Remove Helm releases
helm uninstall teleport-agent --namespace teleport-agent
helm uninstall kubernetes-dashboard --namespace kubernetes-dashboard
helm uninstall teleport-cluster --namespace teleport-cluster

# Remove namespaces
kubectl delete namespace teleport-agent
kubectl delete namespace kubernetes-dashboard
kubectl delete namespace teleport-cluster

# Remove RBAC resources
kubectl delete -f k8s/rbac.yaml
```

---

## 📚 References

### Official Documentation

- **Teleport Cluster Deployment**: [https://goteleport.com/docs/zero-trust-access/deploy-a-cluster/helm-deployments/kubernetes-cluster/](https://goteleport.com/docs/zero-trust-access/deploy-a-cluster/helm-deployments/kubernetes-cluster/)
- **Self-Signed Certificates**: [https://goteleport.com/docs/zero-trust-access/deploy-a-cluster/self-signed-certs/](https://goteleport.com/docs/zero-trust-access/deploy-a-cluster/self-signed-certs/)
- **Kubernetes Dashboard with Teleport**: [https://github.com/gravitational/teleport/discussions/31811](https://github.com/gravitational/teleport/discussions/31811)

### Additional Resources

- **Teleport Documentation**: [https://goteleport.com/docs/](https://goteleport.com/docs/)
- **Kubernetes Dashboard**: [https://github.com/kubernetes/dashboard](https://github.com/kubernetes/dashboard)
- **Teleport Kube Agent Chart**: [https://artifacthub.io/packages/helm/teleport/teleport-kube-agent](https://artifacthub.io/packages/helm/teleport/teleport-kube-agent)
- **Kubernetes Dashboard Chart**: [https://artifacthub.io/packages/helm/k8s-dashboard/kubernetes-dashboard](https://artifacthub.io/packages/helm/k8s-dashboard/kubernetes-dashboard)

---

## 📝 License

MIT

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📧 Support

For issues and questions:
- Open an issue in the repository
- Check the [Troubleshooting](#-troubleshooting) section
- Refer to the [References](#-references) links
