#!/bin/bash
# 一键部署 JDK 21 Runner 到 Kubernetes

set -e

# ==================== 配置区 ====================
NAMESPACE="msa-dev"
HARBOR_URL="harbor-develop.zuzuche.net"
HARBOR_USER="admin"
HARBOR_PASSWORD="your-password-here"  # 建议从环境变量读取
# ===============================================

echo "=========================================="
echo "Deploying JDK 21 GitLab Runner to K8s"
echo "=========================================="
echo "Namespace: ${NAMESPACE}"
echo "=========================================="

# 检查 kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found!"
    exit 1
fi

# 检查必要文件
REQUIRED_FILES=(
    "jdk21-runner-serviceaccount.yaml"
    "jdk21-runner-rbac.yaml"
    "jdk21-runner-configmap.yaml"
    "jdk21-runner-statefulset.yaml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "Error: $file not found!"
        exit 1
    fi
done

# 检查 ConfigMap 中是否还有占位符
if grep -q "RUNNER_TOKEN_HERE_REPLACE_ME" jdk21-runner-configmap.yaml; then
    echo ""
    echo "⚠️  WARNING: ConfigMap contains placeholder token!"
    echo ""
    echo "You need to:"
    echo "1. Register runner to get Runner Token"
    echo "2. Replace 'RUNNER_TOKEN_HERE_REPLACE_ME' with real token"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 1
    fi
fi

# 步骤 1: 创建 Namespace
echo ""
echo "Step 1: Creating namespace..."
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "✓ Namespace $NAMESPACE already exists"
else
    kubectl create namespace "$NAMESPACE"
    echo "✓ Namespace $NAMESPACE created"
fi

# 步骤 2: 创建 ImagePullSecret
echo ""
echo "Step 2: Creating Harbor ImagePullSecret..."
if kubectl get secret harbor-develop-registry-key -n "$NAMESPACE" &> /dev/null; then
    echo "✓ Secret harbor-develop-registry-key already exists"
    read -p "Recreate secret? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete secret harbor-develop-registry-key -n "$NAMESPACE"
        kubectl create secret docker-registry harbor-develop-registry-key \
            --docker-server="$HARBOR_URL" \
            --docker-username="$HARBOR_USER" \
            --docker-password="$HARBOR_PASSWORD" \
            -n "$NAMESPACE"
        echo "✓ Secret recreated"
    fi
else
    kubectl create secret docker-registry harbor-develop-registry-key \
        --docker-server="$HARBOR_URL" \
        --docker-username="$HARBOR_USER" \
        --docker-password="$HARBOR_PASSWORD" \
        -n "$NAMESPACE"
    echo "✓ Secret created"
fi

# 步骤 3: 部署 ServiceAccount
echo ""
echo "Step 3: Deploying ServiceAccount..."
kubectl apply -f jdk21-runner-serviceaccount.yaml -n "$NAMESPACE"
echo "✓ ServiceAccount applied"

# 步骤 4: 部署 RBAC
echo ""
echo "Step 4: Deploying RBAC..."
kubectl apply -f jdk21-runner-rbac.yaml -n "$NAMESPACE"
echo "✓ RBAC applied"

# 步骤 5: 部署 ConfigMap
echo ""
echo "Step 5: Deploying ConfigMap..."
kubectl apply -f jdk21-runner-configmap.yaml -n "$NAMESPACE"
echo "✓ ConfigMap applied"

# 步骤 6: 部署 StatefulSet
echo ""
echo "Step 6: Deploying StatefulSet..."
kubectl apply -f jdk21-runner-statefulset.yaml -n "$NAMESPACE"
echo "✓ StatefulSet applied"

# 步骤 7: 等待 Pod 启动
echo ""
echo "Step 7: Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=jdk21-runner -n "$NAMESPACE" --timeout=300s || {
    echo "⚠️  Pods not ready after 5 minutes, checking status..."
    kubectl get pods -n "$NAMESPACE" -l app=jdk21-runner
}

# 显示部署结果
echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo ""
echo "Pods:"
kubectl get pods -n "$NAMESPACE" -l app=jdk21-runner
echo ""
echo "PVCs:"
kubectl get pvc -n "$NAMESPACE" -l app=jdk21-runner
echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Verify runner connectivity:"
echo "   kubectl exec -n $NAMESPACE jdk21-runner-0 -c gitlab-runner -- gitlab-runner verify"
echo ""
echo "2. Check runner logs:"
echo "   kubectl logs -n $NAMESPACE jdk21-runner-0 -c gitlab-runner --tail=50"
echo ""
echo "3. View runner config:"
echo "   kubectl exec -n $NAMESPACE jdk21-runner-0 -c gitlab-runner -- cat /etc/gitlab-runner/config.toml"
echo ""
echo "4. Configure Docker login (if needed):"
echo "   ./scripts/docker-login-in-pods.sh $NAMESPACE"
echo ""
echo "See README.md for detailed usage"
echo "=========================================="
