#!/bin/bash

###############################################################################
# K3s Server (Master Node) Installation Script
# Optimized for 8GB RAM system with 2-node cluster
# This script installs the K3s server (control plane + worker)
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
K3S_VERSION="${K3S_VERSION:-v1.28.5+k3s1}"  # Stable version
TOKEN_FILE="/var/lib/rancher/k3s/server/node-token"
KUBECONFIG_FILE="/etc/rancher/k3s/k3s.yaml"

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
        log_info "Usage: sudo $0"
        exit 1
    fi
}

# Check system requirements
check_system_requirements() {
    log_info "Checking system requirements..."

    # Check memory (8GB system, need to be conservative)
    total_mem=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 7 ]; then
        log_error "System has ${total_mem}GB RAM. This script is designed for 8GB+ systems"
        exit 1
    else
        log_success "System has ${total_mem}GB RAM (Target: 8GB)"
    fi

    # Check CPU
    cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 2 ]; then
        log_warning "System has ${cpu_cores} CPU cores. Recommended: 2+ cores"
    else
        log_success "System has ${cpu_cores} CPU cores"
    fi

    # Check disk space
    available_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 20 ]; then
        log_warning "Available disk space: ${available_space}GB. Recommended: 20GB+"
    else
        log_success "Available disk space: ${available_space}GB"
    fi
}

# Check if K3s is already installed
check_existing_k3s() {
    if command -v k3s &> /dev/null; then
        log_warning "K3s is already installed"
        k3s --version | head -n1

        echo ""
        read -p "Do you want to UNINSTALL and reinstall K3s? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Uninstalling existing K3s..."
            /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
            sleep 3
            log_success "K3s uninstalled"
        else
            log_info "Keeping existing K3s installation"
            log_info "Skipping to configuration steps..."
            return 1
        fi
    fi
    return 0
}

# Install K3s server node
install_k3s_server() {
    log_info "Installing K3s server node..."
    log_info "Version: ${K3S_VERSION}"

    # K3s installation with resource-conscious settings
    # --disable: Disable unnecessary components to save resources (~300MB saved)
    # --disable servicelb: Using NodePort instead of LoadBalancer for demo
    # --disable traefik: We don't need ingress controller for this demo (~150MB saved)
    # --disable metrics-server: Can enable later if needed (~50MB saved)
    # --kubelet-arg: Resource reservations for system stability on 8GB RAM

    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" sh -s - server \
        --write-kubeconfig-mode 644 \
        --disable traefik \
        --disable servicelb \
        --disable metrics-server \
        --node-name k3s-master \
        --bind-address 0.0.0.0 \
        --kubelet-arg="kube-reserved=memory=1Gi" \
        --kubelet-arg="system-reserved=memory=512Mi" \
        --kubelet-arg="eviction-hard=memory.available<256Mi" \
        --kube-apiserver-arg="--service-node-port-range=30000-32767"

    if [ $? -eq 0 ]; then
        log_success "K3s server installed successfully"
    else
        log_error "K3s server installation failed"
        exit 1
    fi
}

# Wait for K3s to be ready
wait_for_k3s() {
    log_info "Waiting for K3s to be ready..."

    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if k3s kubectl get nodes &> /dev/null; then
            log_success "K3s cluster is accessible"
            break
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done
    echo ""

    if [ $attempt -eq $max_attempts ]; then
        log_error "Timeout waiting for K3s cluster"
        exit 1
    fi

    # Wait for node to be Ready
    log_info "Waiting for master node to be ready..."
    k3s kubectl wait --for=condition=Ready nodes --all --timeout=300s

    log_success "K3s server is ready"
}

# Configure kubectl for non-root user
configure_kubectl() {
    log_info "Configuring kubectl for non-root users..."

    local REAL_USER="${SUDO_USER:-$USER}"
    local USER_HOME=$(eval echo ~$REAL_USER)

    if [ "$REAL_USER" != "root" ]; then
        # Create .kube directory
        mkdir -p "$USER_HOME/.kube"

        # Copy kubeconfig
        cp "$KUBECONFIG_FILE" "$USER_HOME/.kube/config"
        chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.kube"
        chmod 600 "$USER_HOME/.kube/config"

        log_success "kubectl configured for user: $REAL_USER"
        log_info "Kubeconfig location: $USER_HOME/.kube/config"
    fi
}

# Save node token for worker nodes
save_node_token() {
    log_info "Saving node token for worker registration..."

    # Wait for token file to be created
    local max_attempts=30
    local attempt=0

    while [ ! -f "$TOKEN_FILE" ] && [ $attempt -lt $max_attempts ]; do
        sleep 1
        attempt=$((attempt + 1))
    done

    if [ -f "$TOKEN_FILE" ]; then
        local TOKEN=$(cat "$TOKEN_FILE")
        local SERVER_IP=$(hostname -I | awk '{print $1}')

        # Save token and server info
        cat > /var/lib/rancher/k3s/server/cluster-info.txt <<EOF
# K3s Cluster Information
# Generated: $(date)

SERVER_IP=$SERVER_IP
SERVER_URL=https://${SERVER_IP}:6443
NODE_TOKEN=$TOKEN

# To join a worker node, run on the worker machine:
# curl -sfL https://get.k3s.io | K3S_URL=https://${SERVER_IP}:6443 K3S_TOKEN=${TOKEN} sh -s - agent --node-name k3s-worker-1
EOF

        chmod 600 /var/lib/rancher/k3s/server/cluster-info.txt

        log_success "Cluster information saved to: /var/lib/rancher/k3s/server/cluster-info.txt"

        echo ""
        log_header "Worker Node Join Command"
        echo ""
        log_info "To add a worker node, run this command on the worker machine:"
        echo ""
        echo -e "${GREEN}curl -sfL https://get.k3s.io | K3S_URL=https://${SERVER_IP}:6443 K3S_TOKEN=${TOKEN} sh -s - agent --node-name k3s-worker-1${NC}"
        echo ""
        log_info "Or use the provided script: sudo ./02-add-worker-node.sh ${SERVER_IP} ${TOKEN}"
        echo ""
    else
        log_error "Failed to find node token file"
    fi
}

# Verify installation
verify_installation() {
    log_info "Verifying K3s installation..."
    echo ""

    log_info "=== Cluster Information ==="
    k3s kubectl cluster-info
    echo ""

    log_info "=== Node Status ==="
    k3s kubectl get nodes -o wide
    echo ""

    log_info "=== System Pods ==="
    k3s kubectl get pods -A
    echo ""

    log_info "=== Resource Usage ==="
    free -h
    echo ""
}

# Install Helm
install_helm() {
    log_info "Checking for Helm..."

    if command -v helm &> /dev/null; then
        log_success "Helm is already installed ($(helm version --short 2>/dev/null || echo 'version check failed'))"
        return 0
    fi

    log_info "Installing Helm 3..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    if [ $? -eq 0 ]; then
        log_success "Helm installed successfully"
        helm version --short
    else
        log_error "Helm installation failed"
        exit 1
    fi
}

# Create namespace for Druid
create_druid_namespace() {
    log_info "Creating namespace for Druid..."

    k3s kubectl create namespace druid-cluster 2>/dev/null || log_info "Namespace already exists"
    k3s kubectl label namespace druid-cluster name=druid-cluster --overwrite

    log_success "Namespace 'druid-cluster' is ready"
}

# Enable kubectl for current session
enable_kubectl() {
    log_info "Enabling kubectl command..."

    # Create symlink for easier kubectl access
    if [ ! -L /usr/local/bin/kubectl ]; then
        ln -s /usr/local/bin/k3s /usr/local/bin/kubectl
        log_success "kubectl command enabled"
    fi
}

# Print summary
print_summary() {
    local SERVER_IP=$(hostname -I | awk '{print $1}')

    echo ""
    log_header "K3s Server Installation Complete!"
    echo ""

    log_success "Master node is running and ready"
    log_info "Server IP: ${SERVER_IP}"
    log_info "Kubeconfig: /etc/rancher/k3s/k3s.yaml"
    echo ""

    log_info "Next steps:"
    echo "  1. Add a worker node using: sudo ./scripts/02-add-worker-node.sh"
    echo "  2. Verify cluster: kubectl get nodes"
    echo "  3. Check pods: kubectl get pods -A"
    echo "  4. Deploy Druid: ./scripts/03-deploy-druid.sh"
    echo ""

    log_warning "Note: This system has 8GB RAM - resource limits are set conservatively"
    log_warning "Monitor resource usage: watch -n 2 'free -h && echo && kubectl top nodes'"
    echo ""
}

# Main installation flow
main() {
    echo ""
    log_header "K3s Server Installation - 2 Node Cluster Setup"
    echo ""
    log_info "Target: 8GB RAM system optimized configuration"
    echo ""

    check_root
    check_system_requirements
    echo ""

    if check_existing_k3s; then
        install_k3s_server
        sleep 5
        wait_for_k3s
    else
        wait_for_k3s
    fi

    enable_kubectl
    configure_kubectl
    save_node_token
    verify_installation
    install_helm
    create_druid_namespace
    print_summary
}

# Run main function
main
