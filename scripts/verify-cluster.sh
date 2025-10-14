#!/bin/bash

###############################################################################
# K3s Cluster Verification Script
# Comprehensive health check for K3s cluster
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Check kubectl availability
check_kubectl() {
    if command -v kubectl &> /dev/null; then
        log_success "kubectl is available"
        return 0
    else
        log_error "kubectl not found"
        log_info "Trying k3s kubectl..."
        if command -v k3s &> /dev/null; then
            alias kubectl='k3s kubectl'
            log_success "Using k3s kubectl"
            return 0
        fi
        log_error "Neither kubectl nor k3s found. Please install K3s first."
        exit 1
    fi
}

# Check cluster accessibility
check_cluster_access() {
    log_section "Cluster Accessibility"

    if kubectl cluster-info &> /dev/null; then
        log_success "Cluster is accessible"
        kubectl cluster-info | head -2
    else
        log_error "Cannot access cluster"
        log_info "Check if K3s is running: sudo systemctl status k3s"
        exit 1
    fi
}

# Check nodes
check_nodes() {
    log_section "Node Status"

    local total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo 0)

    echo ""
    kubectl get nodes -o wide 2>/dev/null || log_error "Failed to get nodes"
    echo ""

    if [ "$total_nodes" -eq 0 ]; then
        log_error "No nodes found in cluster"
        return 1
    fi

    log_info "Total nodes: ${total_nodes}"
    log_info "Ready nodes: ${ready_nodes}"

    if [ "$ready_nodes" -eq "$total_nodes" ]; then
        log_success "All nodes are Ready"
    else
        log_warning "Some nodes are not Ready (${ready_nodes}/${total_nodes})"
    fi

    if [ "$total_nodes" -lt 2 ]; then
        log_warning "Expected 2 nodes for this setup, found ${total_nodes}"
    fi
}

# Check system pods
check_system_pods() {
    log_section "System Pods Health"

    echo ""
    kubectl get pods -n kube-system -o wide
    echo ""

    local total_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l)
    local running_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    local failed_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c -E "Error|CrashLoopBackOff|ImagePullBackOff" || echo 0)

    log_info "Total system pods: ${total_pods}"
    log_info "Running pods: ${running_pods}"

    if [ "$failed_pods" -gt 0 ]; then
        log_error "Failed pods: ${failed_pods}"
        echo ""
        log_info "Failed pods details:"
        kubectl get pods -n kube-system --field-selector status.phase!=Running,status.phase!=Succeeded
    else
        log_success "No failed system pods"
    fi
}

# Check namespaces
check_namespaces() {
    log_section "Namespaces"

    echo ""
    kubectl get namespaces
    echo ""

    if kubectl get namespace druid-cluster &> /dev/null; then
        log_success "druid-cluster namespace exists"
    else
        log_warning "druid-cluster namespace not found"
        log_info "Create it with: kubectl create namespace druid-cluster"
    fi
}

# Check resources
check_resources() {
    log_section "Resource Usage"

    echo ""
    log_info "Memory Usage:"
    free -h
    echo ""

    log_info "Disk Usage:"
    df -h / | grep -v tmpfs
    echo ""

    # Check if metrics-server is available
    if kubectl top nodes &> /dev/null 2>&1; then
        log_info "Node Resource Usage (from metrics-server):"
        kubectl top nodes
        echo ""
    else
        log_warning "metrics-server not available (kubectl top nodes won't work)"
        log_info "This is normal for K3s - metrics-server is disabled by default"
    fi
}

# Check services
check_services() {
    log_section "Services"

    echo ""
    kubectl get svc -A -o wide
    echo ""

    local svc_count=$(kubectl get svc -A --no-headers 2>/dev/null | wc -l)
    log_info "Total services: ${svc_count}"
}

# Check storage
check_storage() {
    log_section "Storage Classes"

    echo ""
    kubectl get sc
    echo ""

    if kubectl get sc local-path &> /dev/null; then
        log_success "local-path storage class available (K3s default)"
    else
        log_warning "local-path storage class not found"
    fi

    echo ""
    log_info "Persistent Volumes:"
    kubectl get pv 2>/dev/null || log_info "No persistent volumes yet"
    echo ""

    log_info "Persistent Volume Claims (all namespaces):"
    kubectl get pvc -A 2>/dev/null || log_info "No PVCs yet"
}

# Check Helm
check_helm() {
    log_section "Helm"

    if command -v helm &> /dev/null; then
        log_success "Helm is installed"
        helm version --short
        echo ""

        log_info "Helm Repositories:"
        helm repo list 2>/dev/null || log_info "No Helm repositories configured"
        echo ""

        log_info "Helm Releases (all namespaces):"
        helm list -A 2>/dev/null || log_info "No Helm releases deployed"
    else
        log_warning "Helm not installed"
        log_info "Install with: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    fi
}

# Check network connectivity
check_network() {
    log_section "Network Connectivity"

    # Check DNS
    log_info "Testing DNS resolution..."
    if kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default &> /dev/null; then
        log_success "DNS is working"
    else
        log_info "Running DNS test..."
        kubectl run dnstest --image=busybox:1.28 --rm -it --restart=Never -- nslookup kubernetes.default || true
        kubectl delete pod dnstest --ignore-not-found=true &> /dev/null
    fi

    # Check pod-to-pod communication
    echo ""
    log_info "Pod Network CIDR:"
    kubectl cluster-info dump 2>/dev/null | grep -m 1 "cluster-cidr" || log_info "N/A"

    echo ""
    log_info "Service CIDR:"
    kubectl cluster-info dump 2>/dev/null | grep -m 1 "service-cluster-ip-range" || log_info "N/A"
}

# Druid-specific checks
check_druid_readiness() {
    log_section "Druid Deployment Readiness"

    # Check if druid namespace exists
    if kubectl get namespace druid-cluster &> /dev/null; then
        log_success "Druid namespace exists"

        # Check for Druid resources
        echo ""
        log_info "Druid resources in druid-cluster namespace:"
        kubectl get all -n druid-cluster 2>/dev/null || log_info "No Druid resources deployed yet"
    else
        log_warning "Druid namespace not created yet"
    fi

    echo ""
    log_info "System readiness for Druid deployment:"

    # Check memory (need at least 4GB free for Druid)
    local available_mem=$(free -g | awk '/^Mem:/{print $7}')
    if [ "$available_mem" -ge 4 ]; then
        log_success "Sufficient memory available: ${available_mem}GB"
    else
        log_warning "Low available memory: ${available_mem}GB (Recommended: 4GB+)"
    fi

    # Check node count
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [ "$node_count" -ge 2 ]; then
        log_success "Multi-node cluster ready: ${node_count} nodes"
    else
        log_warning "Single node cluster (${node_count} node). Multi-node recommended for HA"
    fi

    # Check storage
    if kubectl get sc local-path &> /dev/null; then
        log_success "Storage class available for PVCs"
    else
        log_error "No storage class available"
    fi
}

# Generate summary
print_summary() {
    log_section "Cluster Health Summary"

    local issues=0

    # Check critical components
    local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo 0)
    local total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

    echo ""
    if [ "$ready_nodes" -eq "$total_nodes" ] && [ "$total_nodes" -gt 0 ]; then
        log_success "Nodes: ${ready_nodes}/${total_nodes} Ready"
    else
        log_error "Nodes: ${ready_nodes}/${total_nodes} Ready"
        issues=$((issues + 1))
    fi

    local running_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    local total_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l)
    if [ "$running_pods" -eq "$total_pods" ] && [ "$total_pods" -gt 0 ]; then
        log_success "System Pods: ${running_pods}/${total_pods} Running"
    else
        log_warning "System Pods: ${running_pods}/${total_pods} Running"
        issues=$((issues + 1))
    fi

    if kubectl get sc local-path &> /dev/null; then
        log_success "Storage: Available"
    else
        log_error "Storage: Not Available"
        issues=$((issues + 1))
    fi

    if command -v helm &> /dev/null; then
        log_success "Helm: Installed"
    else
        log_warning "Helm: Not Installed"
        issues=$((issues + 1))
    fi

    echo ""
    if [ $issues -eq 0 ]; then
        log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_success "  Cluster is healthy and ready!"
        log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
        log_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_warning "  Found ${issues} issue(s) - review above"
        log_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
    echo ""
}

# Main verification flow
main() {
    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║   K3s Cluster Verification Report    ║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════╝${NC}"

    check_kubectl
    check_cluster_access
    check_nodes
    check_system_pods
    check_namespaces
    check_resources
    check_storage
    check_services
    check_helm
    check_network
    check_druid_readiness
    print_summary

    echo ""
    log_info "Verification complete!"
    log_info "Run this script anytime to check cluster health: ./scripts/verify-cluster.sh"
    echo ""
}

# Run main function
main
