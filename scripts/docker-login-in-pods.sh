#!/bin/bash
# 在 Runner Pod 中执行 Docker Login（登录到 Harbor）
# 用法：./docker-login-in-pods.sh [namespace]

set -e

NAMESPACE="${1:-msa-dev}"
RUNNER_NAME="jdk21-runner"

# Harbor 配置（根据实际情况修改）
HARBOR_URL="harbor-develop.zuzuche.net"
HARBOR_USER="admin"
HARBOR_PASSWORD="your-password-here"

echo "=========================================="
echo "Docker Login Script for Runner Pods"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "Runner: $RUNNER_NAME"
echo "Harbor: $HARBOR_URL"
echo "=========================================="

# 获取 Pod 列表
PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$RUNNER_NAME" -o jsonpath='{.items[*].metadata.name}')

if [ -z "$PODS" ]; then
    echo "Error: No pods found for runner: $RUNNER_NAME in namespace: $NAMESPACE"
    exit 1
fi

echo "Found pods: $PODS"
echo ""

# 对每个 Pod 执行 docker login
for POD in $PODS; do
    echo "----------------------------------------"
    echo "Logging into Harbor on pod: $POD"
    echo "----------------------------------------"

    kubectl exec -n "$NAMESPACE" "$POD" -c gitlab-runner -- \
        sh -c "echo '$HARBOR_PASSWORD' | docker login $HARBOR_URL -u '$HARBOR_USER' --password-stdin"

    if [ $? -eq 0 ]; then
        echo "✓ Successfully logged in on pod: $POD"
    else
        echo "✗ Failed to login on pod: $POD"
    fi
    echo ""
done

echo "=========================================="
echo "Docker login completed!"
echo "=========================================="
echo "Note: This login is temporary and will be lost after pod restart."
echo "For persistent login, configure docker login in CI pipeline."
