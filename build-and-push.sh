#!/bin/bash
# 一键构建并推送 JDK 21 Runner 镜像

set -e

# ==================== 配置区 ====================
HARBOR_URL="harbor-develop.zuzuche.net"
IMAGE_NAME="ptjg-runner/jdk21-runner"
IMAGE_TAG="1.0"

FULL_IMAGE="${HARBOR_URL}/${IMAGE_NAME}:${IMAGE_TAG}"
# ===============================================

echo "=========================================="
echo "Building JDK 21 GitLab Runner Image"
echo "=========================================="
echo "Image: ${FULL_IMAGE}"
echo "=========================================="

# 检查必要文件
if [ ! -f "Base_Dockerfile" ]; then
    echo "Error: Base_Dockerfile not found!"
    exit 1
fi

if [ ! -f ".m2/settings.xml" ]; then
    echo "Warning: .m2/settings.xml not found, using default Maven settings"
fi

# 构建镜像
echo ""
echo "Step 1: Building Docker image..."
docker build -f Base_Dockerfile -t "${FULL_IMAGE}" .

if [ $? -ne 0 ]; then
    echo "Error: Docker build failed!"
    exit 1
fi

echo ""
echo "✓ Build completed successfully!"

# 验证镜像
echo ""
echo "Step 2: Verifying image..."
echo "----------------------------------------"
echo "Java version:"
docker run --rm "${FULL_IMAGE}" java -version
echo ""
echo "Maven version:"
docker run --rm "${FULL_IMAGE}" mvn -version
echo ""
echo "GitLab Runner version:"
docker run --rm "${FULL_IMAGE}" gitlab-runner --version
echo "----------------------------------------"

# 推送镜像
echo ""
read -p "Push image to Harbor? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Step 3: Pushing to Harbor..."
    docker push "${FULL_IMAGE}"

    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ Push completed successfully!"
    else
        echo ""
        echo "✗ Push failed!"
        exit 1
    fi
else
    echo "Skipped push to Harbor"
fi

echo ""
echo "=========================================="
echo "Build Summary"
echo "=========================================="
echo "Image: ${FULL_IMAGE}"
echo "Status: Ready"
echo ""
echo "Next steps:"
echo "1. Register runner to get Runner Token"
echo "2. Update jdk21-runner-configmap.yaml"
echo "3. Deploy to Kubernetes"
echo ""
echo "See README.md for detailed instructions"
echo "=========================================="
