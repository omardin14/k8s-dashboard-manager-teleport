#!/usr/bin/env python3
"""
Main Entry Point

This is the main entry point for the Kubernetes Dashboard Manager with Teleport.
Handles deployment, cleanup, and utility commands.
"""

import sys
from deploy import main as deploy_main
from clean import main as clean_main
from utils import get_tokens, get_clusterip, show_status, show_helm_status, show_logs
from deploy.common import print_error


def main():
    """Main entry point."""
    # If no arguments, default to deployment
    if len(sys.argv) == 1:
        try:
            deploy_main()
        except KeyboardInterrupt:
            print("\n⚠️  Deployment interrupted by user")
            sys.exit(130)
        except Exception as e:
            print_error(f"Fatal error: {e}")
            sys.exit(1)
        return
    
    # Get command from first argument
    command = sys.argv[1]
    
    try:
        if command == "deploy":
            deploy_main()
        elif command == "clean":
            clean_main()
        elif command == "get-tokens":
            get_tokens()
        elif command == "get-clusterip":
            get_clusterip()
        elif command == "status":
            show_status()
        elif command == "helm-status":
            show_helm_status()
        elif command == "logs":
            show_logs()
        else:
            print(f"❌ Unknown command: {command}")
            print()
            print("Available commands:")
            print("  deploy        - Deploy Teleport, Dashboard, and Agent (default)")
            print("  clean         - Clean up all deployed resources")
            print("  get-tokens    - Get dashboard access tokens")
            print("  get-clusterip - Get dashboard ClusterIP")
            print("  status        - Show overall status")
            print("  helm-status   - Show Helm deployment status")
            print("  logs          - Interactive menu to view logs")
            print()
            print("Usage:")
            print("  python3 src/main.py [command]")
            print("  python3 src/main.py          # Defaults to 'deploy'")
            sys.exit(1)
    except KeyboardInterrupt:
        print("\n⚠️  Interrupted by user")
        sys.exit(130)
    except Exception as e:
        print_error(f"Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
