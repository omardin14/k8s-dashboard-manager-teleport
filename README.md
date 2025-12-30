# Kubernetes Dashboard Manager with Teleport

A complete Kubernetes solution that deploys the Kubernetes Dashboard and makes it accessible via Teleport Application Access with both admin and readonly access roles.

![Status](https://img.shields.io/badge/status-ready-green)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## 📑 Table of Contents

- [Quick Start](#-quick-start)
- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Teleport Setup](#-teleport-setup)
- [Architecture](#-architecture)
- [Deployment](#-deployment)
- [Accessing the Dashboard](#-accessing-the-dashboard)
- [Configuration](#-configuration)
- [Security](#-security)
- [Troubleshooting](#-troubleshooting)
- [Cleanup](#-cleanup)
- [Reference](#-reference)

---

## 🚀 Quick Start

### Prerequisites

- Kubernetes cluster (minikube, EKS, GKE, AKS, etc.)
- Teleport tenant/instance configured
- `kubectl` configured to access your cluster
- `helm` installed (v3.x)
- Access to Teleport tenant to generate join tokens

### Fastest Deployment

**1. Setup Configuration:**
```bash
# Create config file from example
make config

# Edit config.yaml with your Teleport proxy and cluster name:
# - teleport.proxy_addr
# - teleport.cluster_name

# Generate join token automatically (requires tctl)
make generate-token

# OR manually set teleport.join_token in config.yaml
```

**2. Setup Minikube (if using local cluster):**
```bash
make setup-minikube
```

**3. Deploy:**
```bash
make helm-deploy
```

**4. Get Tokens:**
```bash
make get-tokens
```

**5. Access via Teleport:**
- Log into Teleport web UI
- Go to Applications
- Click on `kube-dashboard-admin` or `kube-dashboard-readonly`
- Paste the appropriate token when prompted

---

## ✨ Features

### 📊 Kubernetes Dashboard
- Deploys official Kubernetes Dashboard via Helm
- Latest stable version with all features
- Secure ClusterIP service (not exposed publicly)

### 🔐 Teleport Application Access
- **Admin Access**: Full cluster-admin permissions via `kube-dashboard-admin` app
- **Readonly Access**: Read-only permissions via `kube-dashboard-readonly` app
- Secure access through Teleport proxy
- No need to expose dashboard publicly
- Single sign-on through Teleport

### 🛡️ Security
- Two separate service accounts (admin and readonly)
- Proper RBAC with ClusterRole and ClusterRoleBinding
- Long-lived bearer tokens for dashboard authentication
- Teleport handles all authentication and authorization
- Dashboard only accessible via Teleport

---

## 📋 Prerequisites

### Required
- **Kubernetes Cluster**: Any Kubernetes distribution (minikube, EKS, GKE, AKS, etc.)
- **Teleport Tenant**: Active Teleport instance (Cloud or self-hosted)
- **kubectl**: Configured to access your cluster
- **helm**: Version 3.x installed

### Optional
- **minikube**: For local development/testing
- **tctl**: Teleport CLI tool (for generating join tokens)

---

## 🔧 Teleport Setup

### Step 1: Create Teleport Join Token

You need to create a join token in your Teleport tenant that allows both `kube` and `app` roles.

#### Option A: Automatic Generation (Recommended)

If you have `tctl` installed and configured:

```bash
make generate-token
```

This will:
1. Check if `tctl` is available and configured
2. Generate a join token with 24-hour TTL
3. Automatically update `config.yaml` with the token

**Prerequisites for automatic generation:**
- `tctl` installed: [Installation Guide](https://goteleport.com/docs/installation/)
- `tctl` configured to connect to your Teleport cluster
- Proper authentication/credentials

#### Option B: Using Teleport Web UI

1. Log into your Teleport web UI
2. Go to **Settings** → **Authentication** → **Tokens**
3. Click **Add Token**
4. Set:
   - **Token Type**: `Kubernetes` and `Application`
   - **Token Name**: `kube-dashboard-token` (or any name)
   - **TTL**: Set appropriate expiration (e.g., 1 hour for testing, longer for production)
5. Click **Generate**
6. **Copy the token** and update `config.yaml`:
   ```yaml
   teleport:
     join_token: "your-token-here"
   ```

#### Option C: Using tctl Manually

If you have `tctl` configured and access to your Teleport cluster:

```bash
tctl tokens add --type=kube,app --ttl=24h kube-dashboard-token
```

Then copy the token and update `config.yaml`.

### Step 2: Configure Teleport Application Access

The Teleport agent will automatically register two applications:
- `kube-dashboard-admin` - For admin access
- `kube-dashboard-readonly` - For readonly access

These will appear in your Teleport web UI under **Applications** after deployment.

### Step 3: Get Your Teleport Proxy Address

Your Teleport proxy address is typically:
- **Teleport Cloud**: `your-tenant.teleport.sh:443`
- **Self-hosted**: `your-proxy-domain.com:443` or `your-proxy-ip:3080`

You can find this in your Teleport web UI or in your Teleport configuration.

### Step 4: Configure Cluster Name

The cluster name should match what you've configured in Teleport. If this is a new cluster:
1. Go to **Kubernetes** in Teleport web UI
2. The cluster name will be shown there, or you can set a custom name
3. Use this name in `config.yaml` as `teleport.cluster_name`

---

## 🏗️ Architecture

The solution consists of:

1. **Kubernetes Dashboard**: 
   - Deployed via official Helm chart
   - Runs in `kubernetes-dashboard` namespace
   - Exposed via ClusterIP service (internal only)

2. **Teleport Kube Agent**:
   - Deployed via Teleport Helm chart
   - Runs in `teleport-agent` namespace
   - Registers Kubernetes cluster with Teleport
   - Registers two applications for dashboard access

3. **RBAC Resources**:
   - `dashboard-admin-account`: ServiceAccount with cluster-admin role
   - `dashboard-readonly-account`: ServiceAccount with readonly ClusterRole
   - Tokens stored in Kubernetes Secrets

```
┌─────────────────────────────────────────┐
│  Kubernetes Cluster                     │
│  ┌───────────────────────────────────┐  │
│  │  Kubernetes Dashboard             │  │
│  │  (ClusterIP Service)               │  │
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │  Teleport Kube Agent              │  │
│  │  - Registers cluster              │  │
│  │  - Registers applications         │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
           │
           │ Teleport Protocol
           │
┌─────────────────────────────────────────┐
│  Teleport Proxy                          │
│  - Authentication                        │
│  - Authorization                         │
│  - Application Access                    │
└─────────────────────────────────────────┘
           │
           │ HTTPS
           │
┌─────────────────────────────────────────┐
│  User Browser                            │
│  - Teleport Web UI                       │
│  - Dashboard Access                      │
└─────────────────────────────────────────┘
```

---

## 📦 Deployment

### Configuration Setup

1. **Copy the example config:**
```bash
make config
```

2. **Edit `config.yaml` with your values:**
```yaml
teleport:
  proxy_addr: "your-tenant.teleport.sh:443"  # Your Teleport proxy
  cluster_name: "my-k8s-cluster"             # Your cluster name in Teleport
  join_token: "your-join-token-here"         # Token from Teleport
  namespace: "teleport-agent"

kubernetes:
  namespace: "kubernetes-dashboard"
```

3. **Note:** `config.yaml` is in `.gitignore` and will NOT be committed

### Deploy with Helm (Recommended)

```bash
# Deploy everything
make helm-deploy
```

This will:
1. Add required Helm repositories
2. Install Kubernetes Dashboard
3. Wait for Dashboard service to be ready
4. Get Dashboard ClusterIP
5. Install Teleport Kube Agent with application access configured

### Manual Deployment

If you prefer to deploy manually:

```bash
# Add Helm repositories
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard
helm repo add teleport https://charts.releases.teleport.dev
helm repo update

# Install Kubernetes Dashboard
helm upgrade --install kubernetes-dashboard \
  kubernetes-dashboard/kubernetes-dashboard \
  --create-namespace \
  --namespace kubernetes-dashboard

# Get Dashboard ClusterIP
export CLUSTER_IP=$(kubectl -n kubernetes-dashboard get svc kubernetes-dashboard \
  -o jsonpath="{.spec.clusterIP}")

# Install Teleport Kube Agent
helm upgrade --install teleport-kube-agent \
  teleport/teleport-kube-agent \
  --create-namespace \
  --namespace teleport-agent \
  --set authToken=YOUR_JOIN_TOKEN \
  --set proxyAddr=your-proxy.teleport.com:443 \
  --set kubeClusterName=your-cluster-name \
  --set roles=kube,app \
  --set apps[0].name=kube-dashboard-admin \
  --set apps[0].uri=https://$CLUSTER_IP \
  --set apps[0].insecure_skip_verify=true \
  --set apps[1].name=kube-dashboard-readonly \
  --set apps[1].uri=https://$CLUSTER_IP \
  --set apps[1].insecure_skip_verify=true
```

---

## 🔑 Accessing the Dashboard

### Step 1: Get Dashboard Tokens

```bash
make get-tokens
```

This will display:
- **Admin Token**: For full cluster access
- **Readonly Token**: For read-only access

### Step 2: Access via Teleport

1. **Log into Teleport Web UI**
   - Go to your Teleport tenant URL
   - Authenticate with your credentials

2. **Navigate to Applications**
   - Click on **Applications** in the sidebar
   - You should see two applications:
     - `kube-dashboard-admin`
     - `kube-dashboard-readonly`

3. **Open Dashboard**
   - Click on the application you want (admin or readonly)
   - Teleport will open the dashboard in a new window/tab

4. **Authenticate with Dashboard**
   - When prompted for a token, paste the appropriate token:
     - Use **admin token** for `kube-dashboard-admin`
     - Use **readonly token** for `kube-dashboard-readonly`
   - Click **Sign In**

5. **Use the Dashboard**
   - You now have access to the Kubernetes Dashboard
   - Admin access allows full cluster management
   - Readonly access allows viewing resources only

---

## ⚙️ Configuration

### config.yaml Structure

```yaml
teleport:
  # Teleport Proxy endpoint (required)
  proxy_addr: "your-tenant.teleport.sh:443"
  
  # Kubernetes cluster name in Teleport (required)
  cluster_name: "my-k8s-cluster"
  
  # Teleport join token (required)
  # Generate from Teleport UI or: tctl tokens add --type=kube,app
  join_token: "your-token-here"
  
  # Teleport agent namespace (optional, default: teleport-agent)
  namespace: "teleport-agent"

kubernetes:
  # Dashboard namespace (optional, default: kubernetes-dashboard)
  namespace: "kubernetes-dashboard"
```

### Environment Variables

You can also set these via environment variables:
- `TELEPORT_PROXY_ADDR`
- `TELEPORT_CLUSTER_NAME`
- `TELEPORT_JOIN_TOKEN`
- `TELEPORT_NAMESPACE`
- `K8S_NAMESPACE`

---

## 🔒 Security

### RBAC Configuration

**Admin Access:**
- ServiceAccount: `dashboard-admin-account`
- Role: `cluster-admin` (full cluster access)
- Token: Stored in `dashboard-admin-token` secret

**Readonly Access:**
- ServiceAccount: `dashboard-readonly-account`
- Role: Custom `dashboard-readonly-role` with:
  - `get`, `list`, `watch` on all resources
  - No create, update, delete, or patch permissions
- Token: Stored in `dashboard-readonly-token` secret

### Security Best Practices

1. **Token Management**:
   - Tokens are stored in Kubernetes Secrets
   - Rotate tokens regularly
   - Use readonly token when possible

2. **Teleport Security**:
   - All access goes through Teleport
   - Teleport handles authentication and authorization
   - Dashboard is not exposed publicly

3. **Network Security**:
   - Dashboard uses ClusterIP (internal only)
   - No NodePort or LoadBalancer exposure
   - All traffic encrypted via Teleport

4. **Access Control**:
   - Use Teleport RBAC to control who can access applications
   - Separate admin and readonly access
   - Audit all access through Teleport

---

## 🐛 Troubleshooting

### Dashboard Not Appearing in Teleport

**Issue**: Applications don't show up in Teleport web UI

**Solutions**:
1. Check Teleport agent logs:
   ```bash
   make logs
   ```

2. Verify join token is correct:
   ```bash
   kubectl get secret teleport-join-token -n teleport-agent
   ```

3. Check Teleport agent pod status:
   ```bash
   kubectl get pods -n teleport-agent
   ```

4. Verify proxy address is correct in config.yaml

### Cannot Access Dashboard

**Issue**: Can access via Teleport but dashboard shows errors

**Solutions**:
1. Verify tokens are valid:
   ```bash
   make get-tokens
   ```

2. Check if tokens exist:
   ```bash
   kubectl get secrets -n kubernetes-dashboard | grep dashboard
   ```

3. If tokens are missing, redeploy RBAC:
   ```bash
   kubectl apply -f k8s/rbac.yaml
   ```

### Teleport Agent Not Starting

**Issue**: Teleport agent pod is in CrashLoopBackOff

**Solutions**:
1. Check pod logs:
   ```bash
   kubectl logs -n teleport-agent -l app=teleport-kube-agent
   ```

2. Verify join token format (should be 32 characters)
3. Check proxy address is reachable from cluster
4. Verify cluster name matches Teleport configuration

### Dashboard Service Not Found

**Issue**: Cannot get ClusterIP for dashboard

**Solutions**:
1. Check if dashboard is deployed:
   ```bash
   kubectl get pods -n kubernetes-dashboard
   ```

2. Check service:
   ```bash
   kubectl get svc -n kubernetes-dashboard
   ```

3. Redeploy dashboard if needed:
   ```bash
   helm upgrade --install kubernetes-dashboard \
     kubernetes-dashboard/kubernetes-dashboard \
     --namespace kubernetes-dashboard
   ```

---

## 🧹 Cleanup

### Remove All Resources

```bash
make helm-clean
```

This will:
- Uninstall Teleport Kube Agent
- Uninstall Kubernetes Dashboard
- Remove namespaces (optional, may need manual cleanup)

### Manual Cleanup

```bash
# Remove Helm releases
helm uninstall teleport-kube-agent --namespace teleport-agent
helm uninstall kubernetes-dashboard --namespace kubernetes-dashboard

# Remove namespaces (optional)
kubectl delete namespace teleport-agent
kubectl delete namespace kubernetes-dashboard
```

---

## 📚 Reference

- **Teleport Application Access Guide**: [https://github.com/gravitational/teleport/discussions/31811](https://github.com/gravitational/teleport/discussions/31811)
- **Kubernetes Dashboard**: [https://github.com/kubernetes/dashboard](https://github.com/kubernetes/dashboard)
- **Teleport Documentation**: [https://goteleport.com/docs/](https://goteleport.com/docs/)
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
- Refer to the [Reference](#-reference) links

