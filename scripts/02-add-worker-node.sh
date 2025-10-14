#!/bin/bash

###############################################################################
# K3s Worker Node Installation Script
# Adds a worker node to existing K3s cluster
# Usage: sudo ./02-add-worker-node.sh [SERVER_IP] [TOKEN]
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
K3S_VERSION="${K3S_VERSION:-v1.28.5+k3s1}"
WORKER_NAME="${WORKER_NAME:-k3s-worker-1}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        log_info "Usage: sudo $0 [SERVER_IP] [TOKEN]"
        exit 1
    fi
}

# Parse arguments
parse_arguments() {
    SERVER_IP="$1"
    NODE_TOKEN="$2"

    if [ -z "$SERVER_IP" ] || [ -z "$NODE_TOKEN" ]; then
        log_error "Missing required arguments"
        echo ""
        log_info "Usage: sudo $0 <SERVER_IP> <TOKEN>"
        echo ""
        log_info "Example:"
        echo "  sudo $0 192.168.1.100 K10abc123xyz::server:def456"
        echo ""
        log_info "Get SERVER_IP and TOKEN from master node:"
        echo "  sudo cat /var/lib/rancher/k3s/server/cluster-info.txt"
        echo ""
        exit 1
    fi

    K3S_URL="https://${SERVER_IP}:6443"

    log_info "Configuration:"
    log_info "  Server IP: ${SERVER_IP}"
    log_info "  Server URL: ${K3S_URL}"
    log_info "  Worker Name: ${WORKER_NAME}"
}

# Check system requirements
check_system_requirements() {
    log_info "Checking system requirements..."

    # Check memory
    total_mem=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 2 ]; then
        log_warning "System has ${total_mem}GB RAM. Recommended: 2GB+ for worker node"
    else
        log_success "System has ${total_mem}GB RAM"
    fi

    # Check CPU
    cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 2 ]; then
        log_warning "System has ${cpu_cores} CPU cores. Recommended: 2+ cores"
    else
        log_success "System has ${cpu_cores} CPU cores"
    fi

    # Check connectivity to server
    log_info "Testing connectivity to master node..."
    if ping -c 1 -W 2 "$SERVER_IP" &> /dev/null; then
        log_success "Master node is reachable at ${SERVER_IP}"
    else
        log_error "Cannot reach master node at ${SERVER_IP}"
        log_info "Please check network connectivity and firewall rules"
        exit 1
    fi

    # Check API server port connectivity
    log_info "Testing API server connectivity on port 6443..."
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$SERVER_IP/6443" 2>/dev/null; then
        log_success "API server is accessible at ${SERVER_IP}:6443"
    else
        log_error "Cannot connect to API server at ${SERVER_IP}:6443"
        log_info "Possible issues:"
        echo "  - API server not running: Check on master with 'sudo systemctl status k3s'"
        echo "  - Firewall blocking port: On master, run 'sudo ufw allow 6443/tcp'"
        echo "  - Wrong IP address: Verify with 'hostname -I' on master"
        exit 1
    fi
}

# Check if K3s is already installed
check_existing_k3s() {
    if command -v k3s &> /dev/null; then
        log_warning "K3s is already installed on this node"
        k3s --version | head -n1

        echo ""
        read -p "Do you want to UNINSTALL and rejoin as worker? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Uninstalling existing K3s..."
            /usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || \
            /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
            sleep 3
            log_success "K3s uninstalled"
        else
            log_info "Keeping existing installation. Exiting..."
            exit 0
        fi
    fi
}

# Install K3s agent (worker) node
install_k3s_agent() {
    log_info "Installing K3s agent (worker) node..."
    log_info "Joining cluster at: ${K3S_URL}"

    # Install K3s agent with resource-conscious settings
    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_VERSION="${K3S_VERSION}" \
        K3S_URL="${K3S_URL}" \
        K3S_TOKEN="${NODE_TOKEN}" \
        sh -s - agent \
        --node-name "${WORKER_NAME}" \
        --kubelet-arg="kube-reserved=memory=512Mi" \
        --kubelet-arg="system-reserved=memory=256Mi"

    if [ $? -eq 0 ]; then
        log_success "K3s agent installed successfully"
    else
        log_error "K3s agent installation failed"
        exit 1
    fi
}

# Wait for agent to be ready
wait_for_agent() {
    log_info "Waiting for agent to start..."

    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if systemctl is-active --quiet k3s-agent; then
            log_success "K3s agent service is running"
            break
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done
    echo ""

    if [ $attempt -eq $max_attempts ]; then
        log_error "Timeout waiting for K3s agent to start"
        log_info "Check logs: sudo journalctl -u k3s-agent -f"
        exit 1
    fi

    sleep 5
    log_success "Worker node joined the cluster"
}

# Verify installation
verify_installation() {
    log_info "Verifying worker node installation..."
    echo ""

    log_info "=== Service Status ==="
    systemctl status k3s-agent --no-pager -l | head -20
    echo ""

    log_info "To verify from master node, run:"
    echo "  kubectl get nodes -o wide"
    echo "  kubectl get pods -A -o wide"
    echo ""
}

# Print summary
print_summary() {
    local WORKER_IP=$(hostname -I | awk '{print $1}')

    echo ""
    log_header "K3s Worker Node Installation Complete!"
    echo ""

    log_success "Worker node joined the cluster successfully"
    log_info "Worker Name: ${WORKER_NAME}"
    log_info "Worker IP: ${WORKER_IP}"
    log_info "Master IP: ${SERVER_IP}"
    echo ""

    log_info "Next steps:"
    echo "  1. Verify from master: kubectl get nodes"
    echo "  2. Check pod distribution: kubectl get pods -A -o wide"
    echo "  3. Deploy Druid cluster: ./scripts/03-deploy-druid.sh"
    echo ""

    log_info "Useful commands:"
    echo "  - Check logs: sudo journalctl -u k3s-agent -f"
    echo "  - Restart agent: sudo systemctl restart k3s-agent"
    echo "  - Uninstall: sudo /usr/local/bin/k3s-agent-uninstall.sh"
    echo ""
}

# Main installation flow
main() {
    echo ""
    log_header "K3s Worker Node Installation"
    echo ""

    check_root
    parse_arguments "$@"
    echo ""

    check_system_requirements
    echo ""

    check_existing_k3s
    install_k3s_agent
    wait_for_agent
    verify_installation
    print_summary
}

# Run main function
main "$@"
