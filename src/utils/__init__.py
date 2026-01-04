#!/usr/bin/env python3
"""
Utility functions for various operations
"""

#!/usr/bin/env python3
"""
Utility functions for various operations
"""

import sys
import base64
from deploy.common import (
    get_config_value, read_config, run_cmd,
    print_info, print_success, print_warning, print_error
)


def get_tokens():
    """Get dashboard access tokens"""
    print("🔑 Dashboard Access Tokens:")
    print()
    
    config = read_config()
    k8s_ns = get_config_value(config, "kubernetes.namespace", "kubernetes-dashboard")
    
    print_info(f"📋 Using namespace: {k8s_ns}")
    print()
    
    # Get admin token
    print("Admin Token (for dashboard login):")
    exit_code, token_output, _ = run_cmd([
        "kubectl", "get", "secret", "dashboard-token",
        "-n", k8s_ns,
        "-o", "jsonpath={.data.token}"
    ], check=False)
    
    if exit_code == 0 and token_output:
        try:
            token = base64.b64decode(token_output).decode('utf-8')
            print(token)
            print()
            print_success("Copy the token above and paste it into the dashboard login page")
        except Exception:
            print_warning("Failed to decode token")
    else:
        print_warning("Secret 'dashboard-token' not found. Waiting for token generation...")
        print_info("  💡 Run 'make helm-deploy' to create the Secret, then wait a few seconds")
    
    print()
    
    # Get readonly token
    print("Read-only Token:")
    exit_code, readonly_output, _ = run_cmd([
        "kubectl", "get", "secret", "dashboard-readonly-token",
        "-n", k8s_ns,
        "-o", "jsonpath={.data.token}"
    ], check=False)
    
    if exit_code == 0 and readonly_output:
        try:
            readonly_token = base64.b64decode(readonly_output).decode('utf-8')
            print(readonly_token)
        except Exception:
            print_warning("Failed to decode readonly token")
    else:
        print_warning("Secret 'dashboard-readonly-token' not found")
    
    print()


def get_clusterip():
    """Get dashboard ClusterIP"""
    print("🌐 Dashboard ClusterIP:")
    
    config = read_config()
    k8s_ns = get_config_value(config, "kubernetes.namespace", "kubernetes-dashboard")
    
    exit_code, clusterip, _ = run_cmd([
        "kubectl", "-n", k8s_ns,
        "get", "svc", "kubernetes-dashboard",
        "-o", "jsonpath={.spec.clusterIP}"
    ], check=False)
    
    if exit_code == 0 and clusterip:
        print(clusterip)
    else:
        print_warning("Service not found")
    
    print()


def show_status():
    """Show overall status"""
    print("📊 Overall Status:")
    print()
    
    config = read_config()
    k8s_ns = get_config_value(config, "kubernetes.namespace", "kubernetes-dashboard")
    agent_ns = get_config_value(config, "teleport.agent_namespace", "teleport-agent")
    
    print("Namespaces:")
    exit_code, _, _ = run_cmd([
        "kubectl", "get", "namespaces"
    ], check=False)
    
    if exit_code == 0:
        # Filter output
        exit_code, output, _ = run_cmd([
            "kubectl", "get", "namespaces", "-o", "name"
        ], check=False)
        if output:
            for ns in output.strip().split('\n'):
                if k8s_ns in ns or agent_ns in ns:
                    print(f"  {ns}")
    else:
        print_warning("  No namespaces found")
    
    print()
    print(f"Pods in {k8s_ns}:")
    exit_code, _, _ = run_cmd([
        "kubectl", "get", "pods", "-n", k8s_ns
    ], check=False)
    
    if exit_code != 0:
        print_warning("  No pods found")
    
    print()
    print(f"Pods in {agent_ns}:")
    exit_code, _, _ = run_cmd([
        "kubectl", "get", "pods", "-n", agent_ns
    ], check=False)
    
    if exit_code != 0:
        print_warning("  No pods found")
    
    print()
    print("Services:")
    exit_code, output, _ = run_cmd([
        "kubectl", "get", "svc", "-n", k8s_ns
    ], check=False)
    
    if exit_code == 0 and "kubernetes-dashboard" in output:
        for line in output.split('\n'):
            if "kubernetes-dashboard" in line:
                print(f"  {line}")
    else:
        print_warning("  No services found")


def show_helm_status():
    """Show Helm deployment status"""
    print("📊 Helm Deployment Status:")
    print()
    
    config = read_config()
    k8s_ns = get_config_value(config, "kubernetes.namespace", "kubernetes-dashboard")
    agent_ns = get_config_value(config, "teleport.agent_namespace", "teleport-agent")
    
    print(f"Kubernetes Dashboard (namespace: {k8s_ns}):")
    exit_code, output, _ = run_cmd([
        "helm", "status", "kubernetes-dashboard", "--namespace", k8s_ns
    ], check=False)
    
    if exit_code != 0:
        print("  Not installed")
    else:
        print(output)
    
    print()
    print(f"Teleport Agent (namespace: {agent_ns}):")
    exit_code, output, _ = run_cmd([
        "helm", "status", "teleport-agent", "--namespace", agent_ns
    ], check=False)
    
    if exit_code != 0:
        print("  Not installed")
    else:
        print(output)


def show_logs():
    """Interactive menu to view logs"""
    print("📋 Which logs would you like to view?")
    print()
    print("  1) Teleport Server")
    print("  2) Teleport Agent")
    print("  3) Kubernetes Dashboard")
    print("  4) All (show status of all components)")
    print()
    
    try:
        choice = input("Select an option (1-4): ").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        print_warning("Interrupted")
        return
    
    config = read_config()
    cluster_ns = get_config_value(config, "teleport.cluster_namespace", "teleport-cluster")
    agent_ns = get_config_value(config, "teleport.agent_namespace", "teleport-agent")
    k8s_ns = get_config_value(config, "kubernetes.namespace", "kubernetes-dashboard")
    
    if choice == "1":
        print()
        print("📋 Following Teleport Server Logs (Press Ctrl-C to exit):")
        print()
        
        # Try to find auth pod
        exit_code, pod, _ = run_cmd([
            "kubectl", "-n", cluster_ns,
            "get", "pods",
            "-l", "app.kubernetes.io/name=teleport-cluster,app.kubernetes.io/component=auth",
            "-o", "jsonpath={.items[0].metadata.name}"
        ], check=False)
        
        if exit_code == 0 and pod:
            print_info(f"📦 Auth Pod: {pod}")
            print()
            run_cmd(["kubectl", "logs", "-n", cluster_ns, pod, "-f"], check=False)
        else:
            # Try legacy namespace
            exit_code, pod, _ = run_cmd([
                "kubectl", "-n", "teleport",
                "get", "pods",
                "-l", "app=teleport,component=server",
                "-o", "jsonpath={.items[0].metadata.name}"
            ], check=False)
            
            if exit_code == 0 and pod:
                print_info(f"📦 Pod: {pod}")
                print()
                run_cmd(["kubectl", "logs", "-n", "teleport", pod, "-f"], check=False)
            else:
                print_error("Teleport server pod not found")
                print_info("   Run: make helm-deploy")
                sys.exit(1)
    
    elif choice == "2":
        print()
        print("📋 Following Teleport Kube Agent Logs (Press Ctrl-C to exit):")
        print()
        
        # Try multiple ways to find the pod
        exit_code, pod, _ = run_cmd([
            "kubectl", "-n", agent_ns,
            "get", "pods",
            "-l", "app.kubernetes.io/name=teleport-kube-agent",
            "-o", "jsonpath={.items[0].metadata.name}"
        ], check=False)
        
        if not pod:
            exit_code, pod, _ = run_cmd([
                "kubectl", "-n", agent_ns,
                "get", "pods",
                "-l", "app=teleport-kube-agent",
                "-o", "jsonpath={.items[0].metadata.name}"
            ], check=False)
        
        if exit_code == 0 and pod:
            print_info(f"📦 Pod: {pod}")
            print()
            run_cmd(["kubectl", "logs", "-n", agent_ns, pod, "-f"], check=False)
        else:
            print_error(f"No Teleport agent pods found in namespace: {agent_ns}")
            print_info("  Available pods:")
            run_cmd(["kubectl", "-n", agent_ns, "get", "pods"], check=False)
            sys.exit(1)
    
    elif choice == "3":
        print()
        print("📋 Following Kubernetes Dashboard Logs (Press Ctrl-C to exit):")
        print()
        
        # Try multiple ways to find the pod
        exit_code, pod, _ = run_cmd([
            "kubectl", "-n", k8s_ns,
            "get", "pods",
            "-l", "app.kubernetes.io/name=kubernetes-dashboard",
            "-o", "jsonpath={.items[0].metadata.name}"
        ], check=False)
        
        if not pod:
            exit_code, pod, _ = run_cmd([
                "kubectl", "-n", k8s_ns,
                "get", "pods",
                "-l", "app=kubernetes-dashboard",
                "-o", "jsonpath={.items[0].metadata.name}"
            ], check=False)
        
        if exit_code == 0 and pod:
            print_info(f"📦 Pod: {pod}")
            print()
            run_cmd(["kubectl", "logs", "-n", k8s_ns, pod, "-f"], check=False)
        else:
            print_error(f"No dashboard pods found in namespace: {k8s_ns}")
            print_info("  Available pods:")
            run_cmd(["kubectl", "-n", k8s_ns, "get", "pods"], check=False)
            sys.exit(1)
    
    elif choice == "4":
        print()
        print("📊 All Components Status:")
        print()
        
        print("=== Teleport Server (Helm) ===")
        run_cmd([
            "kubectl", "get", "pods", "-n", cluster_ns,
            "-l", "app.kubernetes.io/name=teleport-cluster"
        ], check=False)
        
        print()
        print("=== Teleport Server (Legacy) ===")
        run_cmd([
            "kubectl", "get", "pods", "-n", "teleport",
            "-l", "app=teleport,component=server"
        ], check=False)
        
        print()
        print("=== Teleport Agent ===")
        run_cmd([
            "kubectl", "get", "pods", "-n", agent_ns,
            "-l", "app.kubernetes.io/name=teleport-kube-agent"
        ], check=False)
        
        print()
        print("=== Kubernetes Dashboard ===")
        run_cmd([
            "kubectl", "get", "pods", "-n", k8s_ns,
            "-l", "app.kubernetes.io/name=kubernetes-dashboard"
        ], check=False)
    
    else:
        print()
        print_error("Invalid option. Please select 1, 2, 3, or 4.")
        sys.exit(1)


