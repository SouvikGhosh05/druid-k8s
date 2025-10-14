# Apache Druid on Kubernetes (K3s) - Demo Project

A comprehensive project demonstrating Apache Druid deployment on a K3s (lightweight Kubernetes) cluster with complete documentation, automation scripts, and working demos.

## Project Overview

This project provides:
1. **Automated K3s cluster setup** - Scripts for 2-node cluster installation
2. **Apache Druid deployment** - Using Wiremind Helm chart (modern, K8s-native)
3. **Comprehensive documentation** - Architecture, segmentation, replication, and scaling
4. **Working demos** - Data ingestion and query examples
5. **Resource-optimized configuration** - Designed for 8GB RAM systems

## Project Status

✅ **Phase 1: K3s Cluster Setup - COMPLETE**
- [x] Project directory structure
- [x] K3s server installation script
- [x] Worker node addition script
- [x] Cluster verification script
- [x] Cleanup/uninstall script
- [x] Scripts documentation

✅ **Phase 2: Druid Deployment - COMPLETE**
- [x] Druid deployed via Helm chart
- [x] All components running (Router, Broker, Coordinator, Historical, Indexer, PostgreSQL)
- [x] Deep storage configured (local filesystem)
- [x] Component health verified

✅ **Phase 3: Documentation - COMPLETE**
- [x] Interview preparation guide (DRUID_INTERVIEW_PREPARATION.md)
- [x] Data flow architecture documentation
- [x] Documentation index with recommendations
- [x] Segmentation and replication concepts documented

✅ **Phase 4: Demo & Validation - COMPLETE**
- [x] Multiple sample datasets created (ecommerce, sensor, IoT)
- [x] HTTP server for data ingestion
- [x] Data ingestion tested (2 and 3 partition demos)
- [x] Query examples validated
- [x] Segment structure verified

## Directory Structure

```
druid-k8s/
├── README.md                           # This file
├── DRUID_INTERVIEW_PREPARATION.md      # Comprehensive interview prep guide
├── DRUID_DATA_FLOW_ARCHITECTURE.md     # Practical demo documentation
├── ARCHITECTURE.md                     # Deployment setup & validation
├── DOCUMENTATION_INDEX.md              # Guide to all documentation files
├── serve-sample-data.py                # HTTP server for sample data files
├── start-http-server.sh                # Shell wrapper for HTTP server
│
├── scripts/                            # Automation scripts
│   ├── README.md                       # Scripts documentation
│   ├── 01-install-k3s-server.sh       # Install K3s master node
│   ├── 02-add-worker-node.sh          # Add worker nodes
│   ├── verify-cluster.sh              # Cluster health checks
│   └── cleanup-cluster.sh             # Cluster removal
│
├── demo/                               # Demo resources
│   ├── sample-data/                   # Sample datasets
│   │   ├── sales-data.json            # Original demo data (10 rows)
│   │   ├── ecommerce-orders.json      # E-commerce dataset (100 rows)
│   │   ├── clickstream.json           # Clickstream data
│   │   ├── two-partition-demo.json    # IoT sensors (12 rows, 2 partitions)
│   │   └── three-partition-demo.json  # IoT devices (50 rows, 3 partitions)
│   └── ingestion-specs/               # Ingestion specifications
│       └── sales-ingestion.json       # Example ingestion spec
│
└── docs/                               # Supplementary documentation
    ├── DRUID_COMPLETE_GUIDE.md        # Beginner to intermediate guide
    └── DATA_FLOW_ARCHITECTURE.md      # K8s-native architecture deep dive
```

## Quick Start

### Prerequisites

- **System**: Ubuntu/Debian-based Linux
- **RAM**: 8GB minimum (this project is optimized for this)
- **CPU**: 2+ cores recommended
- **Disk**: 20GB+ free space
- **Network**: Internet connectivity
- **User**: sudo/root access required for installation

### Step 1: Install K3s Master Node

On your first machine (or primary machine for single-node setup):

```bash
cd /home/ubuntu/druid-k8s
sudo ./scripts/01-install-k3s-server.sh
```

**Expected time**: 2-3 minutes

This script will:
- Check system requirements
- Install K3s server with optimized settings
- Configure kubectl
- Install Helm 3
- Create druid-cluster namespace
- Save cluster join information

### Step 2: Add Worker Node (Optional but Recommended)

If you have a second machine for a 2-node cluster:

On the **master node**, get the join command:
```bash
sudo cat /var/lib/rancher/k3s/server/cluster-info.txt
```

On the **worker machine**, run:
```bash
sudo ./scripts/02-add-worker-node.sh <SERVER_IP> <TOKEN>
```

Replace `<SERVER_IP>` and `<TOKEN>` with values from the master node.

### Step 3: Verify Cluster

```bash
./scripts/verify-cluster.sh
```

This provides a comprehensive health check of your cluster.

### Step 4: Access Druid Console

Druid is already deployed and running. Access the console:

```bash
# Get the Router service details
kubectl get svc -n druid-cluster | grep router

# Access Druid Console
# Default: http://localhost:31888
```

Open your browser and navigate to **http://localhost:31888**

### Step 5: Run Sample Data Ingestion

Start the HTTP server to serve sample data files:

```bash
cd /home/ubuntu/druid-k8s

# Start HTTP server (default port 8888)
./start-http-server.sh

# Or specify custom port
./start-http-server.sh 9000
```

Then in Druid Console:
1. Click **"Load data"**
2. Select **"HTTP"**
3. Enter URI: `http://localhost:8888/two-partition-demo.json`
4. Follow the wizard to complete ingestion

## System Architecture

### K3s Cluster Architecture (Current)

```
┌─────────────────────────────────────────────────────────┐
│                   K3s Cluster (2 Nodes)                 │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────────┐         ┌─────────────────┐      │
│  │  Master Node    │         │  Worker Node    │      │
│  │  (k3s-master)   │         │  (k3s-worker-1) │      │
│  ├─────────────────┤         ├─────────────────┤      │
│  │ • K3s Server    │         │ • K3s Agent     │      │
│  │ • Control Plane │         │ • Container     │      │
│  │ • etcd          │         │   Runtime       │      │
│  │ • kubectl       │         │ • Workload      │      │
│  │ • Helm          │         │   Execution     │      │
│  └─────────────────┘         └─────────────────┘      │
│          │                           │                 │
│          └───────────────────────────┘                 │
│                  6443 (API Server)                     │
└─────────────────────────────────────────────────────────┘
```

### Current Druid Architecture (Deployed)

```
┌─────────────────────────────────────────────────────────┐
│              Apache Druid on K3s Cluster                │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌───────────────────────────────────────────────┐     │
│  │            Query Layer                        │     │
│  │  ┌────────┐  ┌────────┐  ┌────────┐         │     │
│  │  │ Router │  │ Broker │  │ Broker │         │     │
│  │  └────────┘  └────────┘  └────────┘         │     │
│  └───────────────────────────────────────────────┘     │
│                         │                              │
│  ┌───────────────────────────────────────────────┐     │
│  │         Master/Coordination Layer             │     │
│  │  ┌─────────────┐  ┌─────────────┐           │     │
│  │  │ Coordinator │  │  Overlord   │           │     │
│  │  └─────────────┘  └─────────────┘           │     │
│  └───────────────────────────────────────────────┘     │
│                         │                              │
│  ┌───────────────────────────────────────────────┐     │
│  │              Data Layer                       │     │
│  │  ┌────────────┐  ┌────────────┐  ┌─────────┐│     │
│  │  │Historical  │  │Historical  │  │ Indexer ││     │
│  │  │  (Tier 1)  │  │  (Tier 2)  │  │ Workers ││     │
│  │  └────────────┘  └────────────┘  └─────────┘│     │
│  └───────────────────────────────────────────────┘     │
│                         │                              │
│  ┌───────────────────────────────────────────────┐     │
│  │          Supporting Services                   │     │
│  │  ┌────────────┐  ┌──────────────────┐        │     │
│  │  │PostgreSQL  │  │  Deep Storage    │        │     │
│  │  │ (Metadata) │  │  (Local/MinIO)   │        │     │
│  │  └────────────┘  └──────────────────┘        │     │
│  └───────────────────────────────────────────────┘     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Resource Allocation (8GB RAM System)

### Current K3s Usage
- K3s server: ~800MB
- System pods: ~500MB
- Available for workloads: ~6.5GB

### Planned Druid Allocation
- PostgreSQL: 512MB
- Broker: 1GB × 1 replica
- Coordinator: 512MB
- Historical: 1GB × 2 replicas
- Indexer: 1GB × 2 replicas
- Router: 256MB

**Total Druid**: ~5.3GB
**System + K3s**: ~1.5GB
**Buffer**: ~1.2GB

## Key Features

### 1. Automated Cluster Management
- One-command master installation
- Simple worker node addition
- Comprehensive health checks
- Clean uninstall process

### 2. Resource Optimization
- Designed specifically for 8GB RAM
- Conservative memory limits
- Efficient component placement
- Monitoring and alerts

### 3. Modern Druid Architecture
- Kubernetes-native service discovery (no ZooKeeper dependency)
- Indexer-based ingestion (modern approach)
- Tiered storage support
- Horizontal scaling ready

### 4. Production-Ready Patterns
- Persistent storage with local-path provisioner
- Namespace isolation
- RBAC and security context
- Health checks and readiness probes

## Common Operations

### Check Cluster Status
```bash
kubectl get nodes -o wide
kubectl get pods -n druid-cluster
./scripts/verify-cluster.sh
```

### Check Druid Components
```bash
# View all Druid pods
kubectl get pods -n druid-cluster

# Check specific component
kubectl logs -n druid-cluster druid-demo-coordinator-0

# Access Druid Console
# http://localhost:31888
```

### View Cluster Resources
```bash
kubectl top nodes              # CPU/Memory per node (if metrics-server enabled)
free -h                        # System memory
df -h                          # Disk usage
```

### Check Ingested Data
```bash
# List all datasources
curl -s http://localhost:31888/druid/coordinator/v1/datasources | jq '.'

# Check segments for a datasource
curl -s http://localhost:31888/druid/coordinator/v1/datasources/two-partition-demo/segments | jq 'length'

# View deep storage structure
tree /mnt/druid-deep-storage/

# Run SQL query
curl -s -X POST http://localhost:31888/druid/v2/sql \
  -H 'Content-Type: application/json' \
  -d '{"query":"SELECT COUNT(*) FROM \"two-partition-demo\""}' | jq '.'
```

### Access Kubernetes Dashboard (Optional)
```bash
# Deploy dashboard (optional)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Create service account and get token
# (Instructions in docs/kubernetes-dashboard.md - to be created)
```

### Cleanup Everything
```bash
sudo ./scripts/cleanup-cluster.sh
```

**⚠️ Warning**: This removes the entire cluster and all data!

## Troubleshooting

### Master node installation fails
```bash
# Check logs
sudo journalctl -u k3s -f

# Verify no existing K3s
ps aux | grep k3s

# Clean up and retry
sudo ./scripts/cleanup-cluster.sh
sudo ./scripts/01-install-k3s-server.sh
```

### Worker node can't join
```bash
# On master, check if API server is listening
sudo netstat -tlnp | grep 6443

# Check firewall
sudo ufw status

# Allow K3s port
sudo ufw allow 6443/tcp

# Test connectivity from worker
ping <master-ip>
telnet <master-ip> 6443
```

### Out of memory errors
```bash
# Check current usage
free -h
kubectl top pods -A

# Reduce Druid replicas in values.yaml
# historical.defaultTier.replicas: 1
# indexer.defaultCategory.replicas: 1

# Monitor continuously
watch -n 2 'free -h && echo && kubectl get pods -n druid-cluster'
```

## Sample Datasets

The project includes several sample datasets for testing and demonstration:

| Dataset | Rows | Partitions | Topic | Use Case |
|---------|------|------------|-------|----------|
| `sales-data.json` | 10 | 1 | Sales transactions | Basic ingestion demo |
| `ecommerce-orders.json` | 100 | 1 | E-commerce orders | Query performance demo |
| `two-partition-demo.json` | 12 | 2 | IoT sensor data | 2-partition segmentation |
| `three-partition-demo.json` | 50 | 3 | IoT device metrics | 3-partition segmentation |
| `clickstream.json` | 31 | 1+ | User clickstream | Behavioral analytics |

### Partition Demo Datasets

**Two-Partition Demo** (12 rows across 2 hours):
- Hour 10:00-11:00: 6 rows
- Hour 11:00-12:00: 6 rows
- Demonstrates: Time-based partitioning with `segmentGranularity=HOUR`

**Three-Partition Demo** (50 rows across 3 hours):
- Hour 10:00-11:00: 17 rows
- Hour 11:00-12:00: 17 rows
- Hour 12:00-13:00: 16 rows
- Demonstrates: Multi-partition segmentation for parallel processing

### Using Sample Data

```bash
# Start HTTP server
./start-http-server.sh

# In Druid Console (http://localhost:31888):
# 1. Load data → HTTP
# 2. URI: http://localhost:8888/three-partition-demo.json
# 3. Set: Segment granularity = HOUR
# 4. Submit and verify 3 segments created
```

## Documentation

Comprehensive documentation is available in the project root and `docs/` directory:

### Primary Documentation (Root Directory)

1. **[DRUID_INTERVIEW_PREPARATION.md](DRUID_INTERVIEW_PREPARATION.md)** - ⭐ **Start Here for Interviews**
   - Complete interview preparation guide with Q&A
   - Segments vs Partitions clarification
   - Data flow with actual logs
   - 15 interview questions answered

2. **[DRUID_DATA_FLOW_ARCHITECTURE.md](DRUID_DATA_FLOW_ARCHITECTURE.md)** - Practical Examples
   - Real cluster examples with actual segment names
   - Scaling demonstration (1 → 2 Historical nodes)
   - Hands-on validation steps

3. **[ARCHITECTURE.md](ARCHITECTURE.md)** - Deployment Guide
   - Helm chart modifications
   - values.yaml configuration
   - Deployment validation steps

4. **[DOCUMENTATION_INDEX.md](DOCUMENTATION_INDEX.md)** - Documentation Guide
   - Overview of all documentation files
   - Recommendations for different use cases
   - Quick decision matrix

### Supplementary Documentation (docs/ Directory)

- **[DRUID_COMPLETE_GUIDE.md](docs/DRUID_COMPLETE_GUIDE.md)** - Beginner to intermediate guide
- **[DATA_FLOW_ARCHITECTURE.md](docs/DATA_FLOW_ARCHITECTURE.md)** - K8s-native architecture deep dive

## Technology Stack

- **Kubernetes**: K3s v1.28.5+k3s1 (lightweight certified Kubernetes)
- **Apache Druid**: 29.0.1 (via Wiremind Helm chart)
- **Container Runtime**: containerd (K3s default)
- **Storage**: local-path provisioner (K3s default)
- **Networking**: Flannel CNI (K3s default)
- **Package Manager**: Helm 3
- **Metadata Store**: PostgreSQL (Bitnami chart)
- **Deep Storage**: Local filesystem (demo) or MinIO/S3 (production)

## Contributing

This is a demo/learning project. Improvements and suggestions welcome!

### Adding Features
1. Create scripts in `scripts/` directory
2. Document in `scripts/README.md`
3. Update main README
4. Test on clean system

### Reporting Issues
- Check `./scripts/verify-cluster.sh` output
- Include system specs (RAM, CPU, OS)
- Provide relevant logs

## Roadmap

- [x] **Phase 1: K3s cluster automation** ✅
- [x] **Phase 2: Druid deployment** ✅
- [x] **Phase 3: Comprehensive documentation** ✅
- [x] **Phase 4: Working demos with real data** ✅
- [ ] Phase 5: Monitoring and observability (Prometheus/Grafana)
- [ ] Phase 6: Advanced features (autoscaling, multi-tier storage)
- [ ] Phase 7: CI/CD integration examples

**Current Status**: All core phases complete. System ready for production-like demos and interview demonstrations.

## References

- [K3s Documentation](https://docs.k3s.io/)
- [Apache Druid Documentation](https://druid.apache.org/docs/latest/)
- [Wiremind Druid Helm Chart](https://github.com/wiremind/wiremind-helm-charts)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)

## License

This project is for educational and demonstration purposes.

## Authors

Created as a comprehensive learning resource for deploying Apache Druid on Kubernetes.

---

**Project Status**: ✅ **All Core Phases Complete** - Fully functional Druid cluster with working demos ✅

**Highlights**:
- ✅ Druid 29.0.1 deployed and operational
- ✅ Multiple sample datasets (2 and 3 partition demos)
- ✅ Comprehensive interview preparation guide
- ✅ HTTP server for easy data ingestion
- ✅ Validated segmentation, replication, and querying

**Ready for**: Interview demonstrations, learning, experimentation, and production-like testing

**Last Updated**: 2025-10-14
