#!/usr/bin/env python3
"""
Common deployment functions shared between local and enterprise modes
"""

import os
import sys
import subprocess
import re
import time
import tempfile
import base64
from pathlib import Path
from typing import Optional, Dict, Tuple

try:
    import yaml
except ImportError:
    print("⚠️  PyYAML is required but not installed.")
    print("📦 Attempting to install PyYAML...")
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "pyyaml>=6.0"], 
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("✅ PyYAML installed successfully!")
        import yaml  # Try importing again
    except (subprocess.CalledProcessError, ImportError):
        print("❌ Failed to automatically install PyYAML.")
        print("💡 Please install it manually:")
        print("   pip install -r src/requirements.txt")
        print("   or")
        print("   pip install pyyaml")
        sys.exit(1)


class Colors:
    """ANSI color codes for terminal output"""
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'


class StepCounter:
    """Counter for tracking deployment steps"""
    def __init__(self, total_steps: int):
        self.current = 0
        self.total = total_steps
    
    def next(self, step_name: str) -> str:
        """Get next step message"""
        self.current += 1
        return f"Step {self.current}/{self.total}: {step_name}"


def print_step(msg: str):
    """Print a step message"""
    print(f"\n{Colors.BOLD}{msg}{Colors.ENDC}")


def print_info(msg: str):
    """Print an info message"""
    print(f"{Colors.OKCYAN}{msg}{Colors.ENDC}")


def print_success(msg: str):
    """Print a success message"""
    print(f"{Colors.OKGREEN}✅ {msg}{Colors.ENDC}")


def print_warning(msg: str):
    """Print a warning message"""
    print(f"{Colors.WARNING}⚠️  {msg}{Colors.ENDC}")


def print_error(msg: str):
    """Print an error message"""
    print(f"{Colors.FAIL}❌ {msg}{Colors.ENDC}")


def run_cmd(cmd: list, check: bool = True, capture_output: bool = False, **kwargs) -> Tuple[int, str, str]:
    """
    Run a shell command and return exit code, stdout, stderr
    """
    try:
        result = subprocess.run(
            cmd,
            check=False,
            capture_output=True,
            text=True,
            **kwargs
        )
        stdout = result.stdout.strip() if result.stdout else ""
        stderr = result.stderr.strip() if result.stderr else ""
        
        if check and result.returncode != 0:
            print_error(f"Command failed: {' '.join(cmd)}")
            if stderr:
                print_error(f"Error: {stderr}")
            sys.exit(1)
        
        return result.returncode, stdout, stderr
    except Exception as e:
        if check:
            print_error(f"Failed to run command: {e}")
            sys.exit(1)
        return 1, "", str(e)


def get_project_root() -> Path:
    """Get the project root directory (parent of src/)"""
    current = Path(__file__).resolve().parent
    # Walk up until we find src/ directory, then return its parent
    while current.name != "src" and current.parent != current:
        current = current.parent
    # If we found src/, return its parent (project root)
    if current.name == "src":
        return current.parent
    # Otherwise, we're already at project root
    return current


def read_config() -> Dict:
    """Read and parse config.yaml"""
    project_root = get_project_root()
    config_path = project_root / "config.yaml"
    if not config_path.exists():
        print_error("config.yaml not found. Run 'make config' first.")
        sys.exit(1)
    
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)
    
    return config


def get_config_value(config: Dict, path: str, default: str = "") -> str:
    """Get a nested config value using dot notation"""
    keys = path.split('.')
    value = config
    for key in keys:
        if isinstance(value, dict) and key in value:
            value = value[key]
        else:
            return default
    return str(value).strip() if value else default


def wait_for_pod(namespace: str, label_selector: str, timeout: int = 120) -> Optional[str]:
    """Wait for a pod to be created and return its name"""
    print_info(f"⏳ Waiting for pod with selector {label_selector}...")
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        exit_code, output, _ = run_cmd([
            "kubectl", "-n", namespace, "get", "pods",
            "-l", label_selector,
            "-o", "jsonpath={.items[0].metadata.name}"
        ], check=False)
        
        if exit_code == 0 and output:
            return output.strip()
        
        time.sleep(2)
    
    return None


def wait_for_pod_ready(namespace: str, pod_name: str, timeout: int = 120) -> bool:
    """Wait for a pod to be ready"""
    print_info(f"⏳ Waiting for pod {pod_name} to be ready...")
    exit_code, _, _ = run_cmd([
        "kubectl", "wait", "--for=condition=ready",
        f"pod/{pod_name}", "-n", namespace,
        f"--timeout={timeout}s"
    ], check=False)
    
    if exit_code == 0:
        print_success(f"Pod {pod_name} is ready")
        return True
    else:
        print_warning(f"Pod {pod_name} may not be fully ready, continuing anyway...")
        return False


def deploy_rbac():
    """Deploy RBAC resources (common to both modes)"""
    print_step("Deploying RBAC resources...")
    project_root = get_project_root()
    run_cmd(["kubectl", "apply", "-f", str(project_root / "k8s/namespace.yaml")])
    run_cmd(["kubectl", "apply", "-f", str(project_root / "k8s/rbac.yaml")])
    print_info("⏳ Waiting for tokens to be generated...")
    time.sleep(5)
    print_success("RBAC resources deployed!")


def deploy_dashboard(config: Dict):
    """Deploy Kubernetes Dashboard (common to both modes)"""
    print_info("🔧 Installing Kubernetes Dashboard...")
    
    k8s_ns = get_config_value(config, "kubernetes.namespace", "kubernetes-dashboard")
    
    # Add helm repo
    run_cmd(["helm", "repo", "add", "kubernetes-dashboard", "https://kubernetes.github.io/dashboard"], check=False)
    run_cmd(["helm", "repo", "update"])
    
    # Deploy Dashboard
    run_cmd([
        "helm", "upgrade", "--install", "kubernetes-dashboard",
        "kubernetes-dashboard/kubernetes-dashboard",
        "--create-namespace",
        "--namespace", k8s_ns,
        "--wait", "--timeout=5m"
    ], check=False)
    
    print_info("⏳ Waiting for Dashboard service to be ready...")
    time.sleep(10)
    
    # Check for dashboard service
    exit_code, _, _ = run_cmd([
        "kubectl", "-n", k8s_ns, "get", "svc",
        "kubernetes-dashboard-kong-proxy"
    ], check=False)
    
    if exit_code != 0:
        print_error("kubernetes-dashboard-kong-proxy service not found.")
        sys.exit(1)
    
    print_success("Kubernetes Dashboard deployed")
    return k8s_ns


def deploy_agent_common(config: Dict, token: str, proxy_clean: str, cluster_name: str, agent_ns: str, k8s_ns: str, is_local: bool = False):
    """Deploy Teleport Agent - common parts"""
    print_info("🔧 Installing Teleport Kube Agent...")
    
    # Add helm repo
    run_cmd(["helm", "repo", "add", "teleport", "https://charts.releases.teleport.dev"], check=False)
    run_cmd(["helm", "repo", "update"])
    
    # Create temp values file
    if is_local:
        # Local mode: use discovery
        temp_values_content = f"""authToken: {token}
proxyAddr: {proxy_clean}
kubeClusterName: {cluster_name}
roles: kube,app,discovery
insecureSkipProxyTLSVerify: true
updater:
  enabled: false
log:
  level: DEBUG
apps: []
appResources:
  - labels:
      app.kubernetes.io/name: kong
      app.kubernetes.io/instance: kubernetes-dashboard
kubernetesDiscovery:
  - types:
    - app
    namespaces:
    - {k8s_ns}
"""
    else:
        # Enterprise mode: use static app config
        exit_code, cluster_ip, _ = run_cmd([
            "kubectl", "-n", k8s_ns, "get", "svc",
            "kubernetes-dashboard-kong-proxy",
            "-o", "jsonpath={.spec.clusterIP}"
        ], check=False)
        
        if not cluster_ip:
            print_error("Failed to get ClusterIP for kubernetes-dashboard-kong-proxy service")
            sys.exit(1)
        
        temp_values_content = f"""authToken: {token}
proxyAddr: {proxy_clean}
kubeClusterName: {cluster_name}
roles: kube,app
updater:
  enabled: false
apps:
  - name: kube-dashboard
    uri: https://{cluster_ip}
    insecure_skip_verify: true
    labels:
      cluster: {cluster_name}
"""
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
        temp_values_file = f.name
        f.write(temp_values_content)
    
    try:
        exit_code, _, stderr = run_cmd([
            "helm", "upgrade", "--install", "teleport-agent",
            "teleport/teleport-kube-agent",
            "--version", "18.6.0",
            "--create-namespace",
            "--namespace", agent_ns,
            "-f", temp_values_file
        ], check=False)
        
        if exit_code != 0:
            print_error("Failed to deploy Teleport agent. Check the error above.")
            print(stderr)
            sys.exit(1)
    finally:
        os.unlink(temp_values_file)
    
    print_success("Teleport agent deployed")

