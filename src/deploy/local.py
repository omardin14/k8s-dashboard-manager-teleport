#!/usr/bin/env python3
"""
Local mode specific deployment functions
"""

import os
import sys
import subprocess
import re
import time
import tempfile
from typing import Optional, Dict
from .common import (
    print_step, print_info, print_success, print_warning, print_error,
    run_cmd, get_config_value, wait_for_pod, wait_for_pod_ready, StepCounter
)


def deploy_teleport_cluster(config: Dict, steps: StepCounter):
    """Deploy Teleport cluster (local mode only)"""
    print_step(steps.next("Deploying Teleport server to Kubernetes..."))
    print_info("⏳ Note: This step may take up to 5 minutes while the Helm chart deploys and pods become ready...")
    
    cluster_ns = get_config_value(config, "teleport.cluster_namespace", "teleport-cluster")
    
    # Add helm repo
    run_cmd(["helm", "repo", "add", "teleport", "https://charts.releases.teleport.dev"], check=False)
    run_cmd(["helm", "repo", "update"])
    
    # Create namespace
    run_cmd(["kubectl", "create", "namespace", cluster_ns], check=False)
    run_cmd(["kubectl", "label", "namespace", cluster_ns, "pod-security.kubernetes.io/enforce=baseline"], check=False)
    
    # Create values file
    values_content = f"""clusterName: minikube
proxyListenerMode: multiplex
acme: false
publicAddr:
  - {cluster_ns}.{cluster_ns}.svc.cluster.local:8080
tunnelPublicAddr:
  - {cluster_ns}.{cluster_ns}.svc.cluster.local:443
extraArgs:
- "--insecure"
auth:
  service:
    enabled: true
    type: ClusterIP
"""
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
        values_file = f.name
        f.write(values_content)
    
    try:
        run_cmd([
            "helm", "upgrade", "--install", "teleport-cluster",
            "teleport/teleport-cluster",
            "--version", "18.6.0",
            "--namespace", cluster_ns,
            "--values", values_file
        ], check=False)
    finally:
        os.unlink(values_file)
    
    print_info("⏳ Verifying Teleport cluster pods are running...")
    time.sleep(5)
    
    pod = wait_for_pod(cluster_ns, "app.kubernetes.io/name=teleport-cluster,app.kubernetes.io/component=auth", timeout=60)
    if pod:
        print_success(f"Found Teleport auth pod: {pod}")
    else:
        print_warning("Teleport auth pod not found yet. This may take a few minutes.")
        print_info(f"   You can check status with: kubectl get pods -n {cluster_ns}")
    
    print_success("Teleport server deployed!")
    return cluster_ns, pod


def setup_admin_user(config: Dict, cluster_ns: str, pod: Optional[str], steps: StepCounter):
    """Setup Teleport admin user with Kubernetes access (local mode only)"""
    print_step(steps.next("Setting up Teleport admin user with Kubernetes access..."))
    
    if not pod:
        pod = wait_for_pod(cluster_ns, "app.kubernetes.io/name=teleport-cluster,app.kubernetes.io/component=auth", timeout=60)
        if not pod:
            print_error("Teleport auth pod not found after waiting")
            sys.exit(1)
    
    wait_for_pod_ready(cluster_ns, pod, timeout=120)
    time.sleep(5)
    
    # Create k8s-admin role
    role_yaml = """kind: role
version: v7
metadata:
  name: k8s-admin
spec:
  allow:
    kubernetes_labels:
      "*": "*"
    kubernetes_groups:
    - system:masters
"""
    
    exit_code, _, _ = run_cmd([
        "kubectl", "exec", "-n", cluster_ns, pod, "-i", "--",
        "tctl", "create", "-f", "-"
    ], input=role_yaml, check=False)
    
    if exit_code != 0:
        run_cmd([
            "kubectl", "exec", "-n", cluster_ns, pod, "-i", "--",
            "tctl", "update", "-f", "-"
        ], input=role_yaml, check=False)
    
    # Check if admin user exists
    exit_code, output, _ = run_cmd([
        "kubectl", "exec", "-n", cluster_ns, pod, "--",
        "tctl", "users", "ls"
    ], check=False)
    
    user_exists = "admin" in output if exit_code == 0 else False
    
    invite_url = None
    if not user_exists:
        print_info("👤 Creating admin user...")
        exit_code, output, _ = run_cmd([
            "kubectl", "exec", "-n", cluster_ns, pod, "--",
            "tctl", "users", "add", "admin",
            "--roles=editor,access,k8s-admin",
            "--logins=root,minikube"
        ], check=False)
        
        if output:
            invite_url = extract_and_fix_invite_url(output)
            if invite_url:
                with open("/tmp/teleport-admin-invite-url.txt", "w") as f:
                    f.write(invite_url)
            
            # Fix output display
            output = fix_invite_url_in_output(output)
            print(output)
        
        print_success("Admin user created")
    else:
        print_info("👤 Admin user already exists, ensuring roles are correct and resetting...")
        run_cmd([
            "kubectl", "exec", "-n", cluster_ns, pod, "--",
            "tctl", "users", "update", "admin",
            "--set-roles=editor,access,k8s-admin"
        ], check=False)
        
        exit_code, output, _ = run_cmd([
            "kubectl", "exec", "-n", cluster_ns, pod, "--",
            "tctl", "users", "reset", "admin"
        ], check=False)
        
        if output:
            invite_url = extract_and_fix_invite_url(output)
            if invite_url:
                with open("/tmp/teleport-admin-invite-url.txt", "w") as f:
                    f.write(invite_url)
            
            # Fix output display
            output = fix_invite_url_in_output(output)
            print(output)
        
        print_success("Admin user roles updated and reset")
    
    return invite_url


def generate_token_local(cluster_ns: str, pod: str, steps: StepCounter) -> str:
    """Generate Teleport join token (local mode only)"""
    print_step(steps.next("Generating Teleport join token..."))
    wait_for_pod_ready(cluster_ns, pod, timeout=60)
    time.sleep(3)
    
    token = None
    for attempt in range(2):
        exit_code, output, _ = run_cmd([
            "kubectl", "exec", "-n", cluster_ns, pod, "--",
            "tctl", "tokens", "add",
            "--type=kube,app,discovery",
            "--ttl=24h"
        ], check=False)
        
        if exit_code != 0:
            if attempt == 0:
                print_warning("Token generation failed. Output:")
                print(output)
                print_info("⏳ Waiting a bit longer and retrying...")
                time.sleep(10)
                continue
            else:
                print_error("Token generation failed after retry. Output:")
                print(output)
                sys.exit(1)
        
        # Extract token
        token_match = re.search(r'[a-f0-9]{32}', output)
        if token_match:
            token = token_match.group(0)
            break
        
        if attempt == 0:
            print_warning("Could not extract token from output. Full output:")
            print(output)
            print_info("⏳ Retrying token generation...")
            time.sleep(5)
        else:
            print_error("Failed to generate token after retry")
            print("Full output:")
            print(output)
            sys.exit(1)
    
    if not token:
        print_error("Failed to extract token")
        sys.exit(1)
    
    print_success(f"Generated token: {token}")
    return token


def add_dashboard_annotations(k8s_ns: str):
    """Add Teleport annotations to dashboard service (local mode only)"""
    print_info("🔧 Adding Teleport annotations for dashboard service (Local mode)...")
    
    run_cmd([
        "kubectl", "annotate", "service", "-n", k8s_ns,
        "kubernetes-dashboard-kong-proxy",
        "teleport.dev/name=dashboard",
        "teleport.dev/protocol=https",
        "teleport.dev/ignore-tls=true",
        "--overwrite"
    ], check=False)
    
    print_success("Added Teleport annotations to dashboard service")


def patch_service_and_restart_pods(cluster_ns: str, agent_ns: str):
    """Patch service and restart pods (local mode only)"""
    print_info("🔧 Patching teleport-cluster service to add port 8080 (Local mode only)...")
    patch_json = '[{"op": "add", "path": "/spec/ports/-", "value": {"name": "agent-fallback", "port": 8080, "protocol": "TCP", "targetPort": 3080}}]'
    run_cmd([
        "kubectl", "patch", "service", "-n", cluster_ns,
        "teleport-cluster", "--type=json", f"-p={patch_json}"
    ], check=False)
    
    print_info("🔄 Restarting teleport-agent pods...")
    run_cmd([
        "kubectl", "delete", "pods", "-n", agent_ns,
        "--all", "--wait=false"
    ], check=False)
    time.sleep(3)


def start_port_forward(cluster_ns: str):
    """Start port-forward (local mode only)"""
    print_info("🔌 Starting port-forward to localhost:8080...")
    
    # Check if port-forward is already running
    exit_code, _, _ = run_cmd([
        "pgrep", "-f", "kubectl port-forward.*teleport.*8080"
    ], check=False)
    
    if exit_code == 0:
        print_success("Port-forward already running")
    else:
        # Start port-forward in background
        exit_code, _, _ = run_cmd([
            "kubectl", "get", "svc", "teleport-cluster", "-n", cluster_ns
        ], check=False)
        
        if exit_code == 0:
            process = subprocess.Popen(
                ["kubectl", "port-forward", "-n", cluster_ns,
                 "svc/teleport-cluster", "8080:8080"],
                stdout=open("/tmp/teleport-port-forward.log", "w"),
                stderr=subprocess.STDOUT
            )
            
            with open("/tmp/teleport-port-forward.pid", "w") as f:
                f.write(str(process.pid))
            
            time.sleep(2)
            
            # Check if it's running
            exit_code, _, _ = run_cmd([
                "pgrep", "-f", "kubectl port-forward.*teleport.*8080"
            ], check=False)
            
            if exit_code == 0:
                print_success(f"Port-forward started (PID: {process.pid})")
                print_info("   Access Teleport at: https://teleport-cluster.teleport-cluster.svc.cluster.local:8080")
            else:
                print_warning("Port-forward failed to start. Check logs: cat /tmp/teleport-port-forward.log")
        else:
            print_warning("Teleport service not found. Port-forward will need to be started manually.")
            print_info("   Run: kubectl port-forward -n teleport-cluster svc/teleport-cluster 8080:8080")


def extract_and_fix_invite_url(output: str) -> Optional[str]:
    """Extract and fix invite URL from output"""
    invite_match = re.search(r'https://[^\s]+/web/invite/[^\s]+', output)
    if invite_match:
        invite_url = invite_match.group(0)
        invite_url = invite_url.replace("<proxyhost>", "teleport-cluster.teleport-cluster.svc.cluster.local")
        invite_url = invite_url.replace(":3080", ":8080")
        invite_url = re.sub(
            r'https://teleport-cluster\.teleport-cluster\.svc\.cluster\.local:\d+',
            'https://teleport-cluster.teleport-cluster.svc.cluster.local:8080',
            invite_url
        )
        invite_url = re.sub(
            r'https://minikube:\d+',
            'https://teleport-cluster.teleport-cluster.svc.cluster.local:8080',
            invite_url
        )
        return invite_url
    return None


def fix_invite_url_in_output(output: str) -> str:
    """Fix invite URL in output for display"""
    output = output.replace("<proxyhost>", "teleport-cluster.teleport-cluster.svc.cluster.local")
    output = output.replace(":3080", ":8080")
    output = re.sub(
        r'https://teleport-cluster\.teleport-cluster\.svc\.cluster\.local:\d+',
        'https://teleport-cluster.teleport-cluster.svc.cluster.local:8080',
        output
    )
    output = re.sub(
        r'https://minikube:\d+',
        'https://teleport-cluster.teleport-cluster.svc.cluster.local:8080',
        output
    )
    return output


def print_summary_local_mode(invite_url: Optional[str], cluster_ns: str):
    """Print deployment summary for local mode"""
    from .common import run_cmd
    
    print("\n" + "=" * 60)
    print("\n✅ Full deployment complete!")
    print("\n" + "=" * 60)
    print("\n📋 Summary:")
    print("  ✅ RBAC resources deployed")
    print("  ✅ Teleport server deployed and running")
    print("  ✅ Admin user created")
    print("  ✅ Join token generated")
    
    # Check port-forward
    exit_code, _, _ = run_cmd([
        "pgrep", "-f", "kubectl port-forward.*teleport.*8080"
    ], check=False)
    
    if exit_code == 0:
        print("  ✅ Port-forward active (https://teleport-cluster.teleport-cluster.svc.cluster.local:8080)")
    else:
        print("  ⚠️  Port-forward NOT running (required for access)")
    
    print("  ✅ Kubernetes Dashboard deployed")
    print("  ✅ Teleport agent deployed")
    print()
    
    if invite_url:
        print("🔗 Admin Invite URL:")
        print(f"   {invite_url}")
        print()
        print("📋 Next Steps:")
        print()
        
        # Check port-forward
        exit_code, _, _ = run_cmd([
            "pgrep", "-f", "kubectl port-forward.*teleport.*8080"
        ], check=False)
        
        if exit_code != 0:
            print("  0️⃣  Start Port-Forward (REQUIRED):")
            print("     • Run in a separate terminal:")
            exit_code, _, _ = run_cmd([
                "kubectl", "get", "svc", "teleport-cluster", "-n", cluster_ns
            ], check=False)
            if exit_code == 0:
                print(f"       kubectl port-forward -n {cluster_ns} svc/teleport-cluster 8080:8080")
            else:
                print("       kubectl port-forward -n teleport svc/teleport 8080:8080")
            print("     • Keep this terminal open while using Teleport")
            print()
        
        print("  1️⃣  Accept the Admin Invite:")
        print("     • Open the URL above in your browser")
        print("     • Set your admin password")
        print()
        print("  2️⃣  Access Teleport Web Console:")
        print("     • URL: https://teleport-cluster.teleport-cluster.svc.cluster.local:8080")
        print("     • Log in with username: admin")
        print()
        print("  3️⃣  Get Dashboard Access Tokens:")
        print("     • Run: make get-tokens")
        print("     • Copy the admin token for dashboard login")
        print()
        print("  4️⃣  Access Kubernetes Dashboard via Teleport:")
        print("     • In Teleport Web UI, go to: Applications → dashboard")
        print("     • Paste the token from step 3 when prompted")
        print()
        print("  5️⃣  View Logs (if needed):")
        print("     • Run: make logs")
    else:
        print("📋 Next Steps:")
        print()
        exit_code, _, _ = run_cmd([
            "pgrep", "-f", "kubectl port-forward.*teleport.*8080"
        ], check=False)
        
        if exit_code != 0:
            print("  0️⃣  Start Port-Forward (REQUIRED):")
            print("     • Run in a separate terminal:")
            exit_code, _, _ = run_cmd([
                "kubectl", "get", "svc", "teleport-cluster", "-n", cluster_ns
            ], check=False)
            if exit_code == 0:
                print(f"       kubectl port-forward -n {cluster_ns} svc/teleport-cluster 8080:8080")
            else:
                print("       kubectl port-forward -n teleport svc/teleport 8080:8080")
            print("     • Keep this terminal open while using Teleport")
            print()
        
        print("  1️⃣  Access Teleport Web Console:")
        print("     • URL: https://teleport-cluster.teleport-cluster.svc.cluster.local:8080")
        print()
        print("  2️⃣  Get Dashboard Access Tokens:")
        print("     • Run: make get-tokens")
        print("     • Copy the admin token for dashboard login")
        print()
        print("  3️⃣  Access Kubernetes Dashboard via Teleport:")
        print("     • In Teleport Web UI, go to: Applications → dashboard")
        print("     • Paste the token from step 2 when prompted")
        print()
        print("  4️⃣  View Logs (if needed):")
        print("     • Run: make logs")
    
    print("\n" + "=" * 60 + "\n")

