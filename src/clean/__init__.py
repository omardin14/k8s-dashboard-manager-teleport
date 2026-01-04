#!/usr/bin/env python3
"""
Clean up all deployed resources
"""

#!/usr/bin/env python3
"""
Clean up all deployed resources
"""

import os
import sys
from pathlib import Path
from deploy.common import (
    get_project_root, get_config_value, read_config, run_cmd,
    print_step, print_success, print_info
)


def stop_port_forward():
    """Stop Teleport port-forward"""
    print_step("Step 1/6: Stopping Teleport port-forward...")
    
    # Check for PID file
    pid_file = Path("/tmp/teleport-port-forward.pid")
    if pid_file.exists():
        try:
            with open(pid_file, 'r') as f:
                pid = f.read().strip()
            if pid:
                try:
                    os.kill(int(pid), 0)  # Check if process exists
                    run_cmd(["kill", pid], check=False)
                    print_success(f"Stopped port-forward (PID: {pid})")
                except (OSError, ValueError):
                    pass
        except Exception:
            pass
        pid_file.unlink(missing_ok=True)
    
    # Kill any remaining port-forward processes
    run_cmd(["pkill", "-f", "kubectl port-forward.*teleport.*8080"], check=False)
    print_success("Port-forward cleanup complete")


def uninstall_helm_releases(config):
    """Uninstall all Helm releases"""
    print_step("Step 2/6: Uninstalling Helm releases...")
    
    k8s_ns = get_config_value(config, "kubernetes.namespace", "kubernetes-dashboard")
    agent_ns = get_config_value(config, "teleport.agent_namespace", "teleport-agent")
    cluster_ns = get_config_value(config, "teleport.cluster_namespace", "teleport-cluster")
    
    print_info(f"🗑️  Uninstalling Teleport Agent from namespace: {agent_ns}")
    run_cmd(["helm", "uninstall", "teleport-agent", "--namespace", agent_ns], check=False)
    
    print_info(f"🗑️  Uninstalling Kubernetes Dashboard from namespace: {k8s_ns}")
    run_cmd(["helm", "uninstall", "kubernetes-dashboard", "--namespace", k8s_ns], check=False)
    
    print_info(f"🗑️  Uninstalling Teleport Cluster from namespace: {cluster_ns}")
    run_cmd(["helm", "uninstall", "teleport-cluster", "--namespace", cluster_ns], check=False)
    
    print_success("Helm releases uninstalled")


def cleanup_agent_resources(config):
    """Clean up remaining Teleport Kube Agent resources"""
    print_step("Step 3/6: Cleaning up remaining Teleport Kube Agent resources...")
    
    agent_ns = get_config_value(config, "teleport.agent_namespace", "teleport-agent")
    
    # Delete pods
    run_cmd(["kubectl", "delete", "pod", "-n", agent_ns, "-l", "app.kubernetes.io/name=teleport-kube-agent", "--ignore-not-found=true"], check=False)
    run_cmd(["kubectl", "delete", "pod", "-n", agent_ns, "-l", "app=teleport-kube-agent", "--ignore-not-found=true"], check=False)
    
    # Delete statefulsets
    run_cmd(["kubectl", "delete", "statefulset", "-n", agent_ns, "teleport-agent", "--ignore-not-found=true"], check=False)
    run_cmd(["kubectl", "delete", "statefulset", "-n", agent_ns, "teleport-kube-agent", "--ignore-not-found=true"], check=False)
    
    # Delete secrets
    run_cmd(["kubectl", "delete", "secret", "-n", agent_ns, "-l", "app.kubernetes.io/name=teleport-kube-agent", "--ignore-not-found=true"], check=False)
    run_cmd(["kubectl", "delete", "secret", "-n", agent_ns, "teleport-agent-join-token", "--ignore-not-found=true"], check=False)
    run_cmd(["kubectl", "delete", "secret", "-n", agent_ns, "teleport-kube-agent-join-token", "--ignore-not-found=true"], check=False)
    run_cmd(["kubectl", "delete", "secret", "-n", agent_ns, "teleport-agent-0-state", "--ignore-not-found=true"], check=False)
    run_cmd(["kubectl", "delete", "secret", "-n", agent_ns, "teleport-kube-agent-0-state", "--ignore-not-found=true"], check=False)
    run_cmd(["kubectl", "delete", "secret", "-n", agent_ns, "-l", "app.kubernetes.io/instance=teleport-agent", "--ignore-not-found=true"], check=False)
    run_cmd(["kubectl", "delete", "secret", "-n", agent_ns, "-l", "app.kubernetes.io/instance=teleport-kube-agent", "--ignore-not-found=true"], check=False)
    
    # Delete configmaps
    run_cmd(["kubectl", "delete", "configmap", "-n", agent_ns, "teleport-agent", "--ignore-not-found=true"], check=False)
    run_cmd(["kubectl", "delete", "configmap", "-n", agent_ns, "teleport-kube-agent", "--ignore-not-found=true"], check=False)
    run_cmd(["kubectl", "delete", "configmap", "-n", agent_ns, "-l", "app.kubernetes.io/name=teleport-kube-agent", "--ignore-not-found=true"], check=False)
    
    print_success("Teleport Kube Agent resources cleaned up")


def remove_teleport_server(config):
    """Remove Teleport server"""
    print_step("Step 4/6: Removing Teleport server...")
    
    cluster_ns = get_config_value(config, "teleport.cluster_namespace", "teleport-cluster")
    run_cmd(["helm", "uninstall", "teleport-cluster", "--namespace", cluster_ns], check=False)
    
    print_success("Teleport server removed")


def delete_namespaces(config):
    """Delete all namespaces"""
    print_step("Step 5/6: Deleting namespaces...")
    
    k8s_ns = get_config_value(config, "kubernetes.namespace", "kubernetes-dashboard")
    agent_ns = get_config_value(config, "teleport.agent_namespace", "teleport-agent")
    cluster_ns = get_config_value(config, "teleport.cluster_namespace", "teleport-cluster")
    
    print_info(f"🗑️  Deleting namespace: {agent_ns}")
    run_cmd(["kubectl", "delete", "namespace", agent_ns], check=False)
    
    print_info(f"🗑️  Deleting namespace: {k8s_ns}")
    run_cmd(["kubectl", "delete", "namespace", k8s_ns], check=False)
    
    print_info(f"🗑️  Deleting namespace: {cluster_ns}")
    run_cmd(["kubectl", "delete", "namespace", cluster_ns], check=False)
    
    print_info("🗑️  Deleting namespace: teleport")
    run_cmd(["kubectl", "delete", "namespace", "teleport"], check=False)
    
    print_success("Namespaces deleted")


def remove_rbac_resources():
    """Remove RBAC resources"""
    print_step("Step 6/6: Removing RBAC resources...")
    
    project_root = get_project_root()
    run_cmd(["kubectl", "delete", "-f", str(project_root / "k8s/rbac.yaml")], check=False)
    
    print_success("RBAC resources removed")


def main():
    """Main cleanup function"""
    print("🧹 Cleaning up all resources...")
    print()
    
    config = read_config()
    
    stop_port_forward()
    print()
    
    uninstall_helm_releases(config)
    print()
    
    cleanup_agent_resources(config)
    print()
    
    remove_teleport_server(config)
    print()
    
    delete_namespaces(config)
    print()
    
    remove_rbac_resources()
    print()
    
    print("✅ Full cleanup complete!")
    print()
    print("📋 Cleaned up:")
    print("  ✅ Teleport port-forward stopped")
    print("  ✅ Helm releases uninstalled")
    print("  ✅ Teleport server removed")
    print("  ✅ All namespaces deleted")
    print("  ✅ RBAC resources removed")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n⚠️  Cleanup interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


