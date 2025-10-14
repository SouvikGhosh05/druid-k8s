#!/bin/bash

###############################################################################
# K3s Cluster Cleanup and Uninstall Script
# Removes K3s cluster and all related resources
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

# Confirm cleanup
confirm_cleanup() {
    log_warning "This will COMPLETELY REMOVE K3s and all cluster data!"
    log_warning "This includes:"
    echo "  - K3s server/agent processes"
    echo "  - All containers and pods"
    echo "  - All Kubernetes resources"
    echo "  - Persistent volumes and data"
    echo "  - Network configurations"
    echo "  - kubectl configuration"
    echo ""

    read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
    echo ""

    if [[ ! $REPLY == "yes" ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi

    log_warning "Starting cleanup in 5 seconds... Press Ctrl+C to abort"
    sleep 5
}

# Check what's installed
check_installed() {
    log_info "Checking installed components..."

    if command -v k3s &> /dev/null; then
        log_info "K3s is installed: $(k3s --version | head -n1)"
        K3S_INSTALLED=true

        if systemctl is-active --quiet k3s; then
            log_info "K3s server is running"
            K3S_SERVER=true
        fi

        if systemctl is-active --quiet k3s-agent; then
            log_info "K3s agent is running"
            K3S_AGENT=true
        fi
    else
        log_warning "K3s is not installed"
        K3S_INSTALLED=false
    fi
}

# Stop K3s services
stop_services() {
    log_info "Stopping K3s services..."

    if [ "$K3S_SERVER" = true ]; then
        log_info "Stopping K3s server..."
        systemctl stop k3s 2>/dev/null || true
        log_success "K3s server stopped"
    fi

    if [ "$K3S_AGENT" = true ]; then
        log_info "Stopping K3s agent..."
        systemctl stop k3s-agent 2>/dev/null || true
        log_success "K3s agent stopped"
    fi

    sleep 2
}

# Uninstall K3s
uninstall_k3s() {
    if [ "$K3S_INSTALLED" = true ]; then
        log_info "Uninstalling K3s..."

        # Uninstall agent first (if present)
        if [ "$K3S_AGENT" = true ]; then
            log_info "Running K3s agent uninstaller..."
            if [ -f "/usr/local/bin/k3s-agent-uninstall.sh" ]; then
                /usr/local/bin/k3s-agent-uninstall.sh
                log_success "K3s agent uninstalled"
            fi
        fi

        # Uninstall server (if present)
        if [ "$K3S_SERVER" = true ]; then
            log_info "Running K3s server uninstaller..."
            if [ -f "/usr/local/bin/k3s-uninstall.sh" ]; then
                /usr/local/bin/k3s-uninstall.sh
                log_success "K3s server uninstalled"
            fi
        fi

        # Generic uninstall if specific scripts not found
        if [ -f "/usr/local/bin/k3s-killall.sh" ]; then
            /usr/local/bin/k3s-killall.sh
        fi
    else
        log_info "K3s not installed, skipping uninstall"
    fi
}

# Clean up kubectl configuration
cleanup_kubectl() {
    log_info "Cleaning up kubectl configuration..."

    local REAL_USER="${SUDO_USER:-$USER}"
    local USER_HOME=$(eval echo ~$REAL_USER)

    if [ -f "$USER_HOME/.kube/config" ]; then
        log_info "Removing kubectl config..."
        rm -f "$USER_HOME/.kube/config"
        log_success "kubectl config removed"
    fi

    # Remove kubectl symlink
    if [ -L "/usr/local/bin/kubectl" ]; then
        rm -f /usr/local/bin/kubectl
        log_info "kubectl symlink removed"
    fi
}

# Clean up remaining files
cleanup_remaining_files() {
    log_info "Cleaning up remaining K3s files..."

    local dirs_to_remove=(
        "/etc/rancher"
        "/var/lib/rancher"
        "/var/lib/kubelet"
        "/var/lib/cni"
        "/opt/cni"
        "/run/k3s"
        "/run/flannel"
    )

    for dir in "${dirs_to_remove[@]}"; do
        if [ -d "$dir" ]; then
            log_info "Removing: $dir"
            rm -rf "$dir"
        fi
    done

    log_success "Remaining files cleaned up"
}

# Clean up network interfaces
cleanup_network() {
    log_info "Cleaning up network interfaces..."

    # Remove CNI network interfaces
    local interfaces=$(ip link show | grep -E "cni0|flannel|veth" | awk -F: '{print $2}' | tr -d ' ' || true)

    if [ -n "$interfaces" ]; then
        for iface in $interfaces; do
            log_info "Removing interface: $iface"
            ip link delete "$iface" 2>/dev/null || true
        done
        log_success "Network interfaces cleaned up"
    else
        log_info "No network interfaces to clean up"
    fi
}

# Clean up iptables rules
cleanup_iptables() {
    log_info "Cleaning up iptables rules..."

    # Flush K3s related iptables rules
    iptables -t nat -F 2>/dev/null || true
    iptables -t nat -X 2>/dev/null || true
    iptables -t mangle -F 2>/dev/null || true
    iptables -t mangle -X 2>/dev/null || true
    iptables -F 2>/dev/null || true
    iptables -X 2>/dev/null || true

    log_success "iptables rules cleaned up"
}

# Clean up mounts
cleanup_mounts() {
    log_info "Cleaning up mounts..."

    # Unmount K3s related mounts
    local k3s_mounts=$(mount | grep -E "k3s|kubelet" | awk '{print $3}' || true)

    if [ -n "$k3s_mounts" ]; then
        for mount in $k3s_mounts; do
            log_info "Unmounting: $mount"
            umount "$mount" 2>/dev/null || true
        done
        log_success "Mounts cleaned up"
    else
        log_info "No mounts to clean up"
    fi
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."

    local issues=0

    # Check if K3s binary still exists
    if command -v k3s &> /dev/null; then
        log_warning "K3s binary still present"
        issues=$((issues + 1))
    else
        log_success "K3s binary removed"
    fi

    # Check if services still exist
    if systemctl list-units --all | grep -q k3s; then
        log_warning "K3s services still present"
        issues=$((issues + 1))
    else
        log_success "K3s services removed"
    fi

    # Check for remaining directories
    if [ -d "/var/lib/rancher" ] || [ -d "/etc/rancher" ]; then
        log_warning "Some K3s directories still present"
        issues=$((issues + 1))
    else
        log_success "K3s directories removed"
    fi

    if [ $issues -eq 0 ]; then
        log_success "Cleanup verification passed"
    else
        log_warning "Cleanup completed with ${issues} warning(s)"
    fi
}

# Print summary
print_summary() {
    echo ""
    log_header "Cleanup Complete"
    echo ""

    log_success "K3s cluster has been removed"
    echo ""

    log_info "What was removed:"
    echo "  ✓ K3s server/agent processes"
    echo "  ✓ All containers and pods"
    echo "  ✓ Configuration files"
    echo "  ✓ Network interfaces and rules"
    echo "  ✓ Persistent data"
    echo ""

    log_info "To reinstall K3s:"
    echo "  sudo ./scripts/01-install-k3s-server.sh"
    echo ""
}

# Main cleanup flow
main() {
    echo ""
    log_header "K3s Cluster Cleanup"
    echo ""

    check_root
    check_installed
    echo ""

    if [ "$K3S_INSTALLED" = false ]; then
        log_info "K3s is not installed. Nothing to clean up."
        exit 0
    fi

    confirm_cleanup
    echo ""

    stop_services
    uninstall_k3s
    cleanup_kubectl
    cleanup_remaining_files
    cleanup_network
    cleanup_iptables
    cleanup_mounts
    verify_cleanup
    print_summary
}

# Run main function
main
