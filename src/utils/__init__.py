#!/usr/bin/env python3
"""
Utility functions for various operations
"""

import sys
import base64
import subprocess
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


def _find_pod_by_labels(namespace, labels_list):
    """Try multiple label selectors to find a pod"""
    for labels in labels_list:
        exit_code, pod, _ = run_cmd([
            "kubectl", "-n", namespace,
            "get", "pods",
            "-l", labels,
            "-o", "jsonpath={.items[0].metadata.name}"
        ], check=False)
        if exit_code == 0 and pod:
            return pod
    return None


def _find_pod_by_name_pattern(namespace, pattern):
    """Fallback: find pod by name pattern"""
    exit_code, output, _ = run_cmd([
        "kubectl", "-n", namespace,
        "get", "pods",
        "-o", "jsonpath={.items[*].metadata.name}"
    ], check=False)
    
    if exit_code == 0 and output:
        pods = output.split()
        for pod in pods:
            if pattern in pod:
                return pod
    return None


def _stream_logs(namespace, pod):
    """Stream kubectl logs directly to terminal (doesn't capture output)"""
    process = None
    try:
        # Use Popen to stream output directly to terminal
        process = subprocess.Popen(
            ["kubectl", "logs", "-n", namespace, pod, "-f"],
            stdout=None,  # Don't capture, stream directly
            stderr=None,  # Don't capture, stream directly
            text=True
        )
        
        # Wait for process (will run until Ctrl-C)
        process.wait()
        return process.returncode
    except KeyboardInterrupt:
        print("\n")
        print_warning("Log streaming interrupted")
        if process:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
        return 0
    except Exception as e:
        print_error(f"Error streaming logs: {e}")
        if process:
            process.terminate()
        return 1


def show_logs():
    """Interactive menu to view logs"""
    config = read_config()
    
    # Determine if we're in local or enterprise mode
    proxy_addr = get_config_value(config, "teleport.proxy_addr", "")
    is_local_mode = not proxy_addr or proxy_addr.strip() == ""
    
    print("📋 Which logs would you like to view?")
    print()
    
    if is_local_mode:
        # Local mode: show Auth, Proxy, Agent, Dashboard, All
        print("  1) Teleport Auth Server")
        print("  2) Teleport Proxy")
        print("  3) Teleport Agent")
        print("  4) Kubernetes Dashboard")
        print("  5) All (show status of all components)")
        print()
        try:
            choice = input("Select an option (1-5): ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            print_warning("Interrupted")
            return
    else:
        # Enterprise mode: show Agent, Dashboard, All only
        print("  1) Teleport Agent")
        print("  2) Kubernetes Dashboard")
        print("  3) All (show status of all components)")
        print()
        try:
            choice = input("Select an option (1-3): ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            print_warning("Interrupted")
            return
        # Map enterprise choices to local mode choices
        if choice == "1":
            choice = "3"  # Agent
        elif choice == "2":
            choice = "4"  # Dashboard
        elif choice == "3":
            choice = "5"  # All
    
    cluster_ns = get_config_value(config, "teleport.cluster_namespace", "teleport-cluster")
    agent_ns = get_config_value(config, "teleport.agent_namespace", "teleport-agent")
    k8s_ns = get_config_value(config, "kubernetes.namespace", "kubernetes-dashboard")
    
    if choice == "1":
        if not is_local_mode:
            print_error("Teleport Auth Server is not available in Enterprise mode")
            print_info("  Auth Server is managed by your Teleport Enterprise/Cloud instance")
            sys.exit(1)
        
        print()
        print("📋 Following Teleport Auth Server Logs (Press Ctrl-C to exit):")
        print()
        
        # Try multiple label selectors
        pod = _find_pod_by_labels(cluster_ns, [
            "app.kubernetes.io/name=teleport-cluster,app.kubernetes.io/component=auth",
            "app.kubernetes.io/component=auth"
        ])
        
        # Fallback to name pattern
        if not pod:
            pod = _find_pod_by_name_pattern(cluster_ns, "auth")
        
        # Try legacy namespace
        if not pod:
            pod = _find_pod_by_labels("teleport", [
                "app=teleport,component=server"
            ])
        
        if pod:
            print_info(f"📦 Auth Pod: {pod}")
            print()
            ns = cluster_ns if pod.startswith("teleport-cluster") else "teleport"
            _stream_logs(ns, pod)
        else:
            print_error("Teleport auth pod not found")
            print_info("  Available pods:")
            exit_code, output, _ = run_cmd(["kubectl", "-n", cluster_ns, "get", "pods"], check=False)
            if output:
                print(output)
            else:
                print("  (no pods found)")
            sys.exit(1)
    
    elif choice == "2":
        if not is_local_mode:
            print_error("Teleport Proxy is not available in Enterprise mode")
            print_info("  Proxy is managed by your Teleport Enterprise/Cloud instance")
            sys.exit(1)
        
        print()
        print("📋 Following Teleport Proxy Logs (Press Ctrl-C to exit):")
        print()
        
        # Try multiple label selectors
        pod = _find_pod_by_labels(cluster_ns, [
            "app.kubernetes.io/name=teleport-cluster,app.kubernetes.io/component=proxy",
            "app.kubernetes.io/component=proxy"
        ])
        
        # Fallback to name pattern
        if not pod:
            pod = _find_pod_by_name_pattern(cluster_ns, "proxy")
        
        if pod:
            print_info(f"📦 Proxy Pod: {pod}")
            print()
            _stream_logs(cluster_ns, pod)
        else:
            print_error("Teleport proxy pod not found")
            print_info("  Available pods:")
            exit_code, output, _ = run_cmd(["kubectl", "-n", cluster_ns, "get", "pods"], check=False)
            if output:
                print(output)
            else:
                print("  (no pods found)")
            sys.exit(1)
    
    elif choice == "3":
        print()
        print("📋 Following Teleport Kube Agent Logs (Press Ctrl-C to exit):")
        print()
        
        # Try multiple label selectors
        pod = _find_pod_by_labels(agent_ns, [
            "app.kubernetes.io/name=teleport-kube-agent",
            "app=teleport-kube-agent"
        ])
        
        # Fallback to name pattern
        if not pod:
            pod = _find_pod_by_name_pattern(agent_ns, "teleport-agent")
        
        if pod:
            print_info(f"📦 Pod: {pod}")
            print()
            _stream_logs(agent_ns, pod)
        else:
            print_error(f"No Teleport agent pods found in namespace: {agent_ns}")
            print_info("  Available pods:")
            exit_code, output, _ = run_cmd(["kubectl", "-n", agent_ns, "get", "pods"], check=False)
            if output:
                print(output)
            else:
                print("  (no pods found)")
            sys.exit(1)
    
    elif choice == "4":
        print()
        print("📋 Following Kubernetes Dashboard Logs (Press Ctrl-C to exit):")
        print()
        
        # Try multiple label selectors
        pod = _find_pod_by_labels(k8s_ns, [
            "app.kubernetes.io/name=kubernetes-dashboard",
            "app=kubernetes-dashboard"
        ])
        
        # Fallback to name pattern
        if not pod:
            pod = _find_pod_by_name_pattern(k8s_ns, "kubernetes-dashboard")
        
        if pod:
            print_info(f"📦 Pod: {pod}")
            print()
            _stream_logs(k8s_ns, pod)
        else:
            print_error(f"No dashboard pods found in namespace: {k8s_ns}")
            print_info("  Available pods:")
            exit_code, output, _ = run_cmd(["kubectl", "-n", k8s_ns, "get", "pods"], check=False)
            if output:
                print(output)
            else:
                print("  (no pods found)")
            sys.exit(1)
    
    elif choice == "5":
        print()
        print("📊 All Components Status:")
        print()
        
        if is_local_mode:
            # Local mode: show Auth, Proxy, Agent, Dashboard
            print("=== Teleport Auth Server ===")
            exit_code, output, _ = run_cmd([
                "kubectl", "get", "pods", "-n", cluster_ns,
                "-l", "app.kubernetes.io/component=auth"
            ], check=False)
            if output:
                print(output)
            else:
                print("  (no pods found)")
            
            print()
            print("=== Teleport Proxy ===")
            exit_code, output, _ = run_cmd([
                "kubectl", "get", "pods", "-n", cluster_ns,
                "-l", "app.kubernetes.io/component=proxy"
            ], check=False)
            if output:
                print(output)
            else:
                print("  (no pods found)")
        else:
            # Enterprise mode: skip Auth and Proxy (not deployed locally)
            print_info("ℹ️  Teleport Auth Server and Proxy are managed by Teleport Enterprise/Cloud")
            print()
        
        print("=== Teleport Agent ===")
        exit_code, output, _ = run_cmd([
            "kubectl", "get", "pods", "-n", agent_ns
        ], check=False)
        if output:
            print(output)
        else:
            print("  (no pods found)")
        
        print()
        print("=== Kubernetes Dashboard ===")
        exit_code, output, _ = run_cmd([
            "kubectl", "get", "pods", "-n", k8s_ns
        ], check=False)
        if output:
            print(output)
        else:
            print("  (no pods found)")
    
    else:
        print()
        if is_local_mode:
            print_error("Invalid option. Please select 1, 2, 3, 4, or 5.")
        else:
            print_error("Invalid option. Please select 1, 2, or 3.")
        sys.exit(1)


