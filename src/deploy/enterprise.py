#!/usr/bin/env python3
"""
Enterprise mode specific deployment functions
"""

#!/usr/bin/env python3
"""
Enterprise mode specific deployment functions
"""

import os
import sys
import re
import time
import platform
from typing import Dict
from .common import (
    print_step, print_info, print_success, print_warning, print_error,
    run_cmd, get_config_value, StepCounter
)


def install_tctl():
    """Install tctl if not found"""
    system = platform.system().lower()
    machine = platform.machine().lower()
    
    if system == "darwin":
        # Try Homebrew first
        exit_code, _, _ = run_cmd(["which", "brew"], check=False)
        if exit_code == 0:
            print_info("Installing tctl via Homebrew...")
            run_cmd(["brew", "install", "teleport"])
            return
        
        # Fallback to direct download
        arch = "amd64" if "x86_64" in machine else "arm64"
        print_warning("Please install tctl manually:")
        print_info("   brew install teleport")
        print_info("   Or download from: https://goteleport.com/download/")
        sys.exit(1)
    elif system == "linux":
        arch = "amd64" if "x86_64" in machine else "arm64"
        print_warning("Please install tctl manually:")
        print_info("   Download from: https://goteleport.com/download/")
        sys.exit(1)
    else:
        print_error(f"Unsupported system: {system}")
        sys.exit(1)


def setup_tctl(config: Dict, steps: StepCounter) -> str:
    """Setup tctl for Teleport Enterprise"""
    print_step(steps.next("Setting up tctl for Teleport Enterprise..."))
    
    proxy = get_config_value(config, "teleport.proxy_addr", "")
    if not proxy:
        print_error("proxy_addr is required for Enterprise mode. Please set it in config.yaml")
        sys.exit(1)
    
    # Check if tctl is installed
    exit_code, _, _ = run_cmd(["which", "tctl"], check=False)
    if exit_code != 0:
        print_info("📦 tctl not found. Installing...")
        install_tctl()
    
    # Configure tctl
    proxy_clean = proxy.replace("https://", "").replace("http://", "")
    if ":" not in proxy_clean:
        proxy_clean = f"{proxy_clean}:443"
    
    os.environ["TELEPORT_PROXY"] = proxy_clean
    
    # Check authentication
    exit_code, output, _ = run_cmd(["tctl", "status"], check=False)
    if exit_code != 0:
        print_warning("tctl is not authenticated to Teleport Enterprise cluster")
        print_info("   Please run the following command to authenticate:")
        print_info(f"   tsh login --user=TELEPORT_USER --proxy={proxy_clean} --auth local")
        print_warning("   ⚠️  Note: Use an authenticator app (TOTP) for MFA, not passkeys.")
        print_info("      See: https://github.com/gravitational/teleport/issues/44600")
        sys.exit(1)
    
    print_success("tctl is configured and authenticated")
    return proxy_clean


def generate_token_enterprise(proxy_clean: str, steps: StepCounter) -> str:
    """Generate Teleport join token (enterprise mode only)"""
    print_step(steps.next("Generating Teleport join token..."))
    
    token = None
    for attempt in range(2):
        exit_code, output, _ = run_cmd([
            "tctl", "tokens", "add",
            "--type=kube,app",
            "--ttl=24h"
        ], check=False)
        
        if exit_code != 0:
            if attempt == 0:
                print_warning("Token generation failed. Output:")
                print(output)
                print_info("⏳ Retrying...")
                time.sleep(5)
                continue
            else:
                print_error("Token generation failed after retry")
                print("Full output:")
                print(output)
                print_info("   This might be due to authentication. Please ensure:")
                print_info(f"   1. You are logged in to Teleport: tsh login --user=TELEPORT_USER --proxy={proxy_clean} --auth local")
                print_warning("      ⚠️  Note: Use an authenticator app (TOTP) for MFA, not passkeys.")
                print_info("         See: https://github.com/gravitational/teleport/issues/44600")
                print_info("   2. Or generate token via Teleport Web UI: Settings → Authentication → Tokens")
                sys.exit(1)
        
        # Extract token
        token_match = re.search(r'[a-f0-9]{32}', output)
        if token_match:
            token = token_match.group(0)
            break
    
    if not token:
        print_error("Failed to extract token")
        sys.exit(1)
    
    print_success(f"Generated token: {token}")
    return token


def print_summary_enterprise_mode(proxy_clean: str):
    """Print deployment summary for enterprise mode"""
    print("\n" + "=" * 60)
    print("\n✅ Full deployment complete!")
    print("\n" + "=" * 60)
    print("\n📋 Summary:")
    print("  ✅ RBAC resources deployed")
    print("  ✅ Kubernetes Dashboard deployed")
    print("  ✅ Teleport agent deployed")
    print()
    print("📋 Next Steps:")
    print()
    print("  1️⃣  Access Teleport Web Console:")
    print(f"     • URL: https://{proxy_clean}")
    print()
    print("  2️⃣  Get Dashboard Access Tokens:")
    print("     • Run: make get-tokens")
    print("     • Copy the admin token for dashboard login")
    print()
    print("  3️⃣  Access Kubernetes Dashboard via Teleport:")
    print("     • In Teleport Web UI, go to: Applications → kube-dashboard")
    print("     • Paste the token from step 2 when prompted")
    print()
    print("  4️⃣  View Logs (if needed):")
    print("     • Run: make logs")
    print("\n" + "=" * 60 + "\n")

