#!/usr/bin/env python3
"""
Kubernetes Dashboard Manager with Teleport - Deployment Module
Orchestrates deployment for both local and enterprise modes
"""

import sys
from .common import (
    read_config, get_config_value, print_info, print_error, print_step, StepCounter,
    deploy_rbac, deploy_dashboard, deploy_agent_common
)
from .local import (
    deploy_teleport_cluster, setup_admin_user, generate_token_local,
    add_dashboard_annotations, patch_service_and_restart_pods,
    start_port_forward, print_summary_local_mode
)
from .enterprise import (
    setup_tctl, generate_token_enterprise, print_summary_enterprise_mode
)


def deploy_local_mode(config):
    """Deploy in local mode"""
    print_info("🚀 Starting local deployment (RBAC + Teleport + Dashboard + Agent)...")
    
    # Local mode has 5 steps
    steps = StepCounter(5)
    
    # Step 1: Deploy RBAC (common)
    print_step(steps.next("Deploying RBAC resources..."))
    deploy_rbac()
    print()
    
    # Step 2: Deploy Teleport cluster (local only)
    cluster_ns, pod = deploy_teleport_cluster(config, steps)
    print()
    
    # Step 3: Setup admin user (local only)
    invite_url = setup_admin_user(config, cluster_ns, pod, steps)
    print()
    
    # Step 4: Generate token (local only)
    token = generate_token_local(cluster_ns, pod, steps)
    proxy_clean = f"{cluster_ns}.{cluster_ns}.svc.cluster.local:443"
    print()
    
    # Step 5: Deploy Dashboard and Agent (common)
    print_step(steps.next("Deploying Dashboard and Teleport Agent..."))
    cluster_name = get_config_value(config, "teleport.cluster_name", "minikube")
    k8s_ns = get_config_value(config, "kubernetes.namespace", "kubernetes-dashboard")
    agent_ns = get_config_value(config, "teleport.agent_namespace", "teleport-agent")
    
    print_info(f"✅ Using token: {token}")
    print_info(f"✅ Using proxy: {proxy_clean}")
    print_info(f"✅ Using cluster: {cluster_name}")
    print_info(f"✅ Using K8S namespace: {k8s_ns}")
    print_info(f"✅ Using Teleport namespace: {agent_ns}")
    
    # Deploy Dashboard (common)
    k8s_ns = deploy_dashboard(config)
    
    # Add annotations (local only)
    add_dashboard_annotations(k8s_ns)
    
    # Deploy Agent (common)
    deploy_agent_common(config, token, proxy_clean, cluster_name, agent_ns, k8s_ns, is_local=True)
    
    # Patch service and restart pods (local only)
    patch_service_and_restart_pods(cluster_ns, agent_ns)
    
    # Start port-forward (local only)
    start_port_forward(cluster_ns)
    
    # Print summary
    print_summary_local_mode(invite_url, cluster_ns)


def deploy_enterprise_mode(config):
    """Deploy in enterprise mode"""
    print_info("🚀 Starting Enterprise deployment (RBAC + Dashboard + Agent)...")
    
    proxy = get_config_value(config, "teleport.proxy_addr", "")
    if not proxy:
        print_error("proxy_addr is required for Enterprise mode. Please set it in config.yaml")
        sys.exit(1)
    
    # Enterprise mode has 4 steps
    steps = StepCounter(4)
    
    # Step 1: Deploy RBAC (common)
    print_step(steps.next("Deploying RBAC resources..."))
    deploy_rbac()
    print()
    
    # Step 2: Setup tctl (enterprise only)
    proxy_clean = setup_tctl(config, steps)
    print()
    
    # Step 3: Generate token (enterprise only)
    token = generate_token_enterprise(proxy_clean, steps)
    print()
    
    # Step 4: Deploy Dashboard and Agent (common)
    print_step(steps.next("Deploying Dashboard and Teleport Agent..."))
    cluster_name = get_config_value(config, "teleport.cluster_name", "minikube")
    k8s_ns = get_config_value(config, "kubernetes.namespace", "kubernetes-dashboard")
    agent_ns = get_config_value(config, "teleport.agent_namespace", "teleport-agent")
    
    if not agent_ns:
        agent_ns = "teleport-agent"
    
    print_info(f"✅ Using token: {token}")
    print_info(f"✅ Using proxy: {proxy_clean}")
    print_info(f"✅ Using cluster: {cluster_name}")
    print_info(f"✅ Using K8S namespace: {k8s_ns}")
    print_info(f"✅ Using Teleport namespace: {agent_ns}")
    
    # Deploy Dashboard (common)
    k8s_ns = deploy_dashboard(config)
    
    # Deploy Agent (common, but with static config for enterprise)
    deploy_agent_common(config, token, proxy_clean, cluster_name, agent_ns, k8s_ns, is_local=False)
    
    # Print summary
    print_summary_enterprise_mode(proxy_clean)


def main():
    """Main deployment function"""
    # Read config
    config = read_config()
    
    # Get proxy address
    proxy = get_config_value(config, "teleport.proxy_addr", "")
    proxy = proxy.strip()
    
    # Validate proxy_addr
    if proxy and not proxy.startswith("https://"):
        print_error("Invalid proxy_addr in config.yaml")
        print_info("   proxy_addr must be either:")
        print_info('   - Empty string "" for local mode')
        print_info('   - Start with "https://" for Enterprise mode (e.g., "https://example.teleport.com:443")')
        print_info(f'   Current value: "{proxy}"')
        sys.exit(1)
    
    # Deploy based on mode
    if not proxy or proxy == "":
        deploy_local_mode(config)
    else:
        deploy_enterprise_mode(config)
