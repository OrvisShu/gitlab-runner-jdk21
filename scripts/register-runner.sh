#!/bin/bash
# 注册 GitLab Runner 并获取 Runner Token
# 在 Pod 内或本机执行此脚本

set -e

# ==================== 配置区 ====================
# GitLab 地址（从 GitLab 页面 Settings -> CI/CD -> Runners 复制）
CI_SERVER_URL="http://git-repositories.zuzuche.com:10081/"

# Registration Token（从 GitLab 页面复制的注册 token）
REGISTRATION_TOKEN="YOUR_REGISTRATION_TOKEN_HERE"

# Runner 标签（多个用逗号分隔）
TAG_LIST="jdk21,maven,java21"

# Runner 描述
DESCRIPTION="jdk21-runner"

# 输出的配置文件路径
OUTPUT_CONFIG="/tmp/runner-config-output.toml"
# ===============================================

echo "=========================================="
echo "GitLab Runner Registration Script"
echo "=========================================="
echo "URL: $CI_SERVER_URL"
echo "Tags: $TAG_LIST"
echo "Description: $DESCRIPTION"
echo "=========================================="

# 检查 gitlab-runner 是否存在
if ! command -v gitlab-runner &> /dev/null; then
    echo "Error: gitlab-runner not found!"
    exit 1
fi

# 执行注册
echo "Registering runner..."
/usr/local/bin/gitlab-runner register \
  --config "$OUTPUT_CONFIG" \
  --non-interactive \
  --url "$CI_SERVER_URL" \
  --registration-token "$REGISTRATION_TOKEN" \
  --executor "shell" \
  --tag-list "$TAG_LIST" \
  --description "$DESCRIPTION"

echo ""
echo "=========================================="
echo "Registration completed!"
echo "=========================================="
echo ""
echo "Generated config file: $OUTPUT_CONFIG"
echo ""
echo "=========================================="
echo "IMPORTANT: Copy the Runner Token below"
echo "=========================================="
echo ""

# 提取并显示 Runner Token
grep 'token = ' "$OUTPUT_CONFIG" || echo "Warning: Could not find token in config"

echo ""
echo "=========================================="
echo "Next Steps:"
echo "1. Copy the 'token = \"...\"' value above"
echo "2. Paste it into jdk21-runner-configmap.yaml"
echo "3. Apply ConfigMap: kubectl apply -f jdk21-runner-configmap.yaml"
echo "4. Restart StatefulSet: kubectl rollout restart statefulset jdk21-runner -n msa-dev"
echo "=========================================="
