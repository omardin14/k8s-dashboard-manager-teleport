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

### Prerequisites

- **Minikube** installed and running
- `kubectl` configured to access your cluster
- `helm` installed (v3.x)
- **macOS/Linux** (for `/etc/hosts` modification)

### Fastest Deployment (Automated - Recommended)

**For local testing with minikube, everything is automated in one command:**

```bash
# 1. Setup minikube (enables required addons)
make setup-minikube

# 2. Deploy everything (one command does it all!)
make helm-deploy
```

**That's it!** The `make helm-deploy` command automatically:
1. ✅ Checks prerequisites (minikube addons, DNS mappings)
2. ✅ Deploys RBAC resources
3. ✅ Deploys Teleport server to Kubernetes
4. ✅ Creates admin user with Kubernetes access
5. ✅ Generates join token
6. ✅ Deploys Kubernetes Dashboard
7. ✅ Deploys Teleport agent with discovery enabled
8. ✅ Patches service to add port 8080
9. ✅ Starts port-forward to `localhost:8080`

**Next steps:**
- Access Teleport Web UI: `https://teleport-cluster.teleport-cluster.svc.cluster.local:8080`
- Accept the admin invite URL shown in the summary
- Get dashboard tokens: `make get-tokens`
- Access dashboard via Teleport: Applications → dashboard

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

### Required
- **Minikube**: For local development/testing
- **kubectl**: Configured to access your cluster
- **helm**: Version 3.x installed
- **macOS/Linux**: For `/etc/hosts` modification

### Minikube Addons
The setup automatically enables:
- `ingress` addon
- `ingress-dns` addon

### DNS Mappings
The setup requires these entries in `/etc/hosts`:
```
127.0.0.1 teleport-cluster.teleport-cluster.svc.cluster.local
127.0.0.1 dashboard.teleport-cluster.teleport-cluster.svc.cluster.local
```

The `make helm-deploy` command will check for these and fail if they're missing.

---

## 🏗️ Architecture

The solution consists of:

1. **Teleport Cluster**: 
   - Deployed via official Helm chart
   - Runs in `teleport-cluster` namespace
   - Web UI on port 8080, tunnel on port 443
   - Self-signed certificates for local testing

2. **Kubernetes Dashboard**: 
   - Deployed via official Helm chart
   - Runs in `kubernetes-dashboard` namespace
   - Exposed via ClusterIP service (internal only)
   - Annotated for Teleport discovery

3. **Teleport Kube Agent**:
   - Deployed via Teleport Helm chart
   - Runs in `teleport-agent` namespace
   - Registers Kubernetes cluster with Teleport
   - Discovers and registers dashboard application
   - Roles: `kube,app,discovery`

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
│  │  - Proxy Service (8080/443)        │  │
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
           │ Port Forward (8080:8080)
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

The setup uses default values for local testing. You can customize via `config.yaml`:

```bash
# Create config file (optional)
make config
```

Edit `config.yaml` if needed:
```yaml
teleport:
  namespace: "teleport-agent"  # Default: teleport-agent

kubernetes:
  namespace: "kubernetes-dashboard"  # Default: kubernetes-dashboard
```

### Automated Deployment

```bash
# Deploy everything
make helm-deploy
```

This will:
1. Check prerequisites (minikube addons, DNS mappings)
2. Deploy RBAC resources
3. Deploy Teleport cluster with:
   - `clusterName: minikube`
   - `proxyListenerMode: multiplex`
   - `publicAddr: teleport-cluster.teleport-cluster.svc.cluster.local:8080`
   - `tunnelPublicAddr: teleport-cluster.teleport-cluster.svc.cluster.local:443`
   - `extraArgs: ["--insecure"]`
4. Create admin user with `k8s-admin` role
5. Generate join token with `kube,app,discovery` roles
6. Deploy Kubernetes Dashboard
7. Annotate dashboard service for Teleport discovery
8. Deploy Teleport Kube Agent with:
   - `roles: kube,app,discovery`
   - `insecureSkipProxyTLSVerify: true`
   - Discovery configuration
9. Patch Teleport service to add port 8080
10. Restart agent pods
11. Start port-forward to `localhost:8080`

**Note:** Step 2 (Teleport deployment) may take up to 5 minutes while the Helm chart deploys and pods become ready.

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

1. **Access Teleport Web UI**
   - URL: `https://teleport-cluster.teleport-cluster.svc.cluster.local:8080`
   - Accept the self-signed certificate warning (expected for local testing)

2. **Accept Admin Invite**
   - Use the invite URL shown in the deployment summary
   - Set your admin password

3. **Navigate to Applications**
   - Click on **Applications** in the sidebar
   - You should see the `dashboard` application (discovered automatically)

4. **Open Dashboard**
   - Click on the `dashboard` application
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
  - teleport-cluster.teleport-cluster.svc.cluster.local:8080
tunnelPublicAddr:
  - teleport-cluster.teleport-cluster.svc.cluster.local:443
extraArgs:
- "--insecure"
auth:
  service:
    enabled: true
    type: ClusterIP
```

### Teleport Kube Agent Configuration

The agent is configured with:

```yaml
roles: kube,app,discovery
insecureSkipProxyTLSVerify: true
updater:
  enabled: false
kubernetesDiscovery:
  - types:
    - app
    namespaces:
    - kubernetes-dashboard
appResources:
  - labels:
      app.kubernetes.io/name: kong
      app.kubernetes.io/instance: kubernetes-dashboard
```

### Dashboard Service Annotations

The dashboard service is annotated for Teleport discovery:

```yaml
teleport.dev/name: dashboard
teleport.dev/protocol: https
teleport.dev/ignore-tls: true
```

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

**🟠 Risk: "Split-Brain" Configuration**

**Configuration:**
- Browser Traffic: Port `8080`.
- Agent Traffic: Port `443`.
- Requires manual Service patching (`kubectl patch service...`) to function.

**Impact:**
High risk of configuration drift. Upgrading the Helm chart will wipe the manual Service patch, causing an immediate outage for all Agents.

- **Production Requirement:** Unified port configuration (443 only) managed strictly via Infrastructure-as-Code (Helm/Terraform) without manual `kubectl` patches.

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
1. Check if port 8080 is already in use:
   ```bash
   lsof -i :8080
   ```

2. Check if the service has port 8080:
   ```bash
   kubectl get svc -n teleport-cluster teleport-cluster -o yaml | grep -A 5 ports
   ```

3. Manually start port-forward:
   ```bash
   kubectl port-forward -n teleport-cluster svc/teleport-cluster 8080:8080
   ```

### Dashboard Not Appearing in Teleport

**Issue**: Applications don't show up in Teleport web UI

**Solutions:**
1. Check Teleport agent logs:
   ```bash
   kubectl logs -n teleport-agent -l app.kubernetes.io/name=teleport-kube-agent
   ```

2. Verify service annotations:
   ```bash
   kubectl get svc -n kubernetes-dashboard kubernetes-dashboard-kong-proxy -o yaml | grep teleport.dev
   ```

3. Check if discovery is enabled:
   ```bash
   kubectl get pods -n teleport-agent -l app.kubernetes.io/name=teleport-kube-agent
   ```

### Cannot Access Teleport Web UI

**Issue**: Can't access `https://teleport-cluster.teleport-cluster.svc.cluster.local:8080`

**Solutions:**
1. Check `/etc/hosts` has the DNS mapping:
   ```bash
   grep teleport-cluster /etc/hosts
   ```

2. Check if port-forward is running:
   ```bash
   pgrep -f "kubectl port-forward.*teleport.*8080"
   ```

3. Check Teleport pods are running:
   ```bash
   kubectl get pods -n teleport-cluster
   ```

### Teleport Agent Not Starting

**Issue**: Teleport agent pod is in CrashLoopBackOff

**Solutions:**
1. Check pod logs:
   ```bash
   kubectl logs -n teleport-agent -l app.kubernetes.io/name=teleport-kube-agent
   ```

2. Verify service has port 8080 (agent needs it):
   ```bash
   kubectl get svc -n teleport-cluster teleport-cluster
   ```

3. Check if service patching succeeded:
   ```bash
   kubectl get svc -n teleport-cluster teleport-cluster -o yaml | grep -A 10 ports
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

This will:
- Stop port-forward
- Uninstall Teleport Kube Agent
- Uninstall Kubernetes Dashboard
- Uninstall Teleport Cluster
- Remove namespaces
- Clean up RBAC resources

### Manual Cleanup

```bash
# Stop port-forward
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
