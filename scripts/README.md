# Automation Scripts

This directory contains automation scripts for setting up and managing the K3s cluster for Apache Druid deployment.

## Script Overview

### Cluster Setup Scripts

#### `01-install-k3s-server.sh`
**Purpose**: Install K3s server (master) node with best practices

**Usage**:
```bash
sudo ./scripts/01-install-k3s-server.sh
```

**What it does**:
- Checks system requirements (8GB RAM, CPU, disk)
- Installs K3s server with resource-optimized settings
- Disables unnecessary components (Traefik, ServiceLB, metrics-server) to save ~300MB RAM
- Configures kubelet memory reservations for system stability
- Sets up kubectl access for non-root users
- Installs Helm 3
- Creates druid-cluster namespace
- Saves cluster join token securely for worker nodes

**Key Features**:
- **Resource Optimization**: Kubelet reserves 1GB for K3s and 512MB for system processes
- **Memory Protection**: Hard eviction at <256MB available to prevent OOM
- **Component Minimization**: Only essential services enabled
- **Security**: Token file permissions set to 600

**Requirements**:
- Must run as root/sudo
- Minimum 7GB RAM (validated during installation)
- 20GB+ disk space
- Internet connectivity

#### `02-add-worker-node.sh`
**Purpose**: Add worker nodes to the cluster with connectivity validation

**Usage**:
```bash
sudo ./scripts/02-add-worker-node.sh <SERVER_IP> <TOKEN>
```

**Example**:
```bash
sudo ./scripts/02-add-worker-node.sh 192.168.1.100 K10abc123xyz::server:def456
```

**Get SERVER_IP and TOKEN from master node**:
```bash
sudo cat /var/lib/rancher/k3s/server/cluster-info.txt
```

**What it does**:
- Validates network connectivity to master node (ping test)
- Tests API server port accessibility (6443/tcp)
- Installs K3s agent with resource reservations
- Joins the cluster automatically
- Configures unique node name

**Key Features**:
- **Connectivity Validation**: Tests both network and API server before installation
- **Resource Optimization**: Kubelet reserves 512MB for K3s and 256MB for system
- **Error Diagnostics**: Provides clear troubleshooting steps on failure
- **Idempotency**: Handles existing installations gracefully

**Requirements**:
- Must run as root/sudo
- Network connectivity to master node
- Master node must be running
- Firewall must allow port 6443/tcp

### Management Scripts

#### `verify-cluster.sh`
**Purpose**: Comprehensive cluster health check

**Usage**:
```bash
./scripts/verify-cluster.sh
```

**What it checks**:
- Cluster accessibility
- Node status (Ready/NotReady)
- System pods health
- Resource usage (CPU, memory, disk)
- Storage classes and PVCs
- Helm installation
- Network connectivity and DNS
- Druid deployment readiness

**Requirements**:
- kubectl or k3s must be installed
- Can run as regular user

#### `cleanup-cluster.sh`
**Purpose**: Complete cluster removal and cleanup

**Usage**:
```bash
sudo ./scripts/cleanup-cluster.sh
```

**What it removes**:
- K3s server/agent processes
- All containers and pods
- Kubernetes resources
- Persistent volumes and data
- Network interfaces and iptables rules
- Configuration files

**⚠️ WARNING**: This is DESTRUCTIVE and IRREVERSIBLE!

**Requirements**:
- Must run as root/sudo
- Will prompt for confirmation

## Quick Start Guide

### Setting Up a 2-Node Cluster

#### Step 1: Install Master Node
On the first machine (master):
```bash
cd /home/ubuntu/druid-k8s
sudo ./scripts/01-install-k3s-server.sh
```

Wait for installation to complete (2-3 minutes).

#### Step 2: Get Join Command
On master node:
```bash
sudo cat /var/lib/rancher/k3s/server/cluster-info.txt
```

Copy the `SERVER_IP` and `NODE_TOKEN` values.

#### Step 3: Add Worker Node
On the second machine (worker):
```bash
cd /home/ubuntu/druid-k8s  # Make sure scripts are available
sudo ./scripts/02-add-worker-node.sh <SERVER_IP> <TOKEN>
```

Replace `<SERVER_IP>` and `<TOKEN>` with actual values from Step 2.

#### Step 4: Verify Cluster
On master node:
```bash
./scripts/verify-cluster.sh
```

Check that both nodes show as "Ready".

#### Step 5: Check Node Status
```bash
kubectl get nodes -o wide
```

Expected output:
```
NAME          STATUS   ROLES                  AGE   VERSION
k3s-master    Ready    control-plane,master   5m    v1.28.5+k3s1
k3s-worker-1  Ready    <none>                 2m    v1.28.5+k3s1
```

## Troubleshooting

### Master node not accessible
**Problem**: Worker can't reach master node

**Solutions**:
```bash
# Check firewall on master
sudo ufw status

# Allow K3s ports (if firewall is enabled)
sudo ufw allow 6443/tcp  # Kubernetes API
sudo ufw allow 10250/tcp # Kubelet

# Check if master is listening
sudo netstat -tlnp | grep 6443
```

### Pods not starting
**Problem**: Pods stuck in Pending or CrashLoopBackOff

**Solutions**:
```bash
# Check pod details
kubectl describe pod <pod-name> -n <namespace>

# Check pod logs
kubectl logs <pod-name> -n <namespace>

# Check node resources
kubectl top nodes
free -h
```

### Storage issues
**Problem**: PVCs not binding

**Solutions**:
```bash
# Check storage class
kubectl get sc

# Check PVC status
kubectl get pvc -A

# Describe PVC for details
kubectl describe pvc <pvc-name> -n <namespace>

# Check local-path provisioner logs
kubectl logs -n kube-system -l app=local-path-provisioner
```

### Network issues
**Problem**: Pods can't communicate

**Solutions**:
```bash
# Check CNI plugin
kubectl get pods -n kube-system | grep flannel

# Test DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Check network policies
kubectl get networkpolicies -A
```

## Resource Considerations for 8GB RAM System

### Memory Allocation Guidelines

**K3s Components (~1.5GB)**:
- K3s server: ~800MB
- System pods: ~500MB
- Kubelet/containerd: ~200MB

**Druid Components (~4-5GB)**:
- PostgreSQL: ~512MB
- Broker: ~1GB
- Coordinator: ~512MB
- Historical (2 replicas): ~2GB
- Indexer (2 replicas): ~2GB
- Router: ~256MB

**System Reserve (~1.5GB)**:
- OS and other processes

**Total: ~7-8GB** (tight but functional)

### Optimization Tips

1. **Reduce replica counts**:
   ```bash
   # In values.yaml
   historical.defaultTier.replicas: 1  # Instead of 2
   indexer.defaultCategory.replicas: 1  # Instead of 2
   ```

2. **Lower memory limits**:
   ```bash
   # Reduce JVM heap sizes
   broker.memory.max: "512m"  # Instead of 1g
   ```

3. **Disable unused components**:
   ```bash
   # Disable router if not needed (access Broker directly)
   router.enabled: false
   ```

4. **Monitor resources**:
   ```bash
   # Watch memory usage
   watch -n 2 'free -h && echo && kubectl top pods -n druid-cluster'
   ```

## Script Maintenance

### Adding New Scripts

1. Create script in this directory
2. Make it executable: `chmod +x <script-name>.sh`
3. Add color-coded logging (use existing scripts as template)
4. Update this README with script documentation

### Testing Scripts

Test scripts on a clean system or VM before using in production:
```bash
# Create test VM with multipass
multipass launch --name k3s-test --cpus 2 --memory 8G --disk 20G

# Copy scripts
multipass transfer druid-k8s k3s-test:/home/ubuntu/

# Test
multipass shell k3s-test
cd /home/ubuntu/druid-k8s
sudo ./scripts/01-install-k3s-server.sh

# Cleanup test VM
multipass delete k3s-test
multipass purge
```

## Additional Resources

- [K3s Documentation](https://docs.k3s.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [Apache Druid on Kubernetes](https://druid.apache.org/docs/latest/operations/kubernetes/)

## Support

If you encounter issues:
1. Run `./scripts/verify-cluster.sh` to diagnose
2. Check logs: `sudo journalctl -u k3s -f`
3. Review K3s logs: `sudo k3s kubectl logs -n kube-system <pod-name>`
