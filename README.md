# JDK 21 GitLab Runner 部署指南

基于 Kubernetes 部署的 JDK 21 GitLab Runner，包含 Maven 3.9、Docker、kubectl 等工具。

## 目录

- [架构说明](#架构说明)
- [前置条件](#前置条件)
- [快速部署](#快速部署)
- [详细步骤](#详细步骤)
- [验证与测试](#验证与测试)
- [CI 配置示例](#ci-配置示例)
- [常见问题](#常见问题)

---

## 架构说明

### 组件清单

| 组件 | 说明 |
|------|------|
| Base_Dockerfile | JDK 21 + Maven 3.9.9 + gitlab-runner + Docker + kubectl |
| ConfigMap | 每个 Pod 对应一个配置文件 (config.0.toml, config.1.toml) |
| StatefulSet | 2 副本，持久化构建目录和 Maven 仓库 |
| ServiceAccount | gitlab-runner (用于 kubectl 操作) |
| RBAC | 授权 Runner 访问 K8s API |

### 技术栈版本

- **JDK**: Eclipse Temurin 21 (OpenJDK 21)
- **Maven**: 3.9.9
- **GitLab Runner**: 17.0.0
- **Docker Client**: 24.0.7
- **kubectl**: v1.28.0

---

## 前置条件

### 1. 准备工作

- K8s 集群访问权限（kubectl 已配置）
- Harbor 镜像仓库访问权限
- GitLab 实例的管理员或项目维护者权限
- Docker 环境（用于构建镜像）

### 2. 准备 Maven settings.xml

编辑 `.m2/settings.xml`，配置：
- Maven 镜像源（如阿里云、私有 Nexus）
- 私有仓库认证信息
- JDK 21 编译配置

### 3. 准备 SSH 密钥（可选）

如需访问私有 Git 仓库，将私钥放到 `.ssh/` 目录：
```bash
cp ~/.ssh/id_rsa .ssh/
chmod 600 .ssh/id_rsa
```

---

## 快速部署

### 总览流程

```
1. 构建并推送 Runner 镜像
   ↓
2. 从 GitLab 获取 Registration Token
   ↓
3. 注册 Runner 获取 Runner Token
   ↓
4. 更新 ConfigMap 中的 Runner Token
   ↓
5. 部署到 K8s
   ↓
6. 验证 Runner 状态
```

### 命令速查

```bash
# 1. 构建镜像
docker build -f Base_Dockerfile -t harbor-develop.zuzuche.net/middleware/jdk21-runner:1.0 .
docker push harbor-develop.zuzuche.net/middleware/jdk21-runner:1.0

# 2. 创建 namespace 和 ImagePullSecret
kubectl create namespace msa-dev
# (创建或复制 harbor-develop-registry-key Secret)

# 3. 部署 K8s 资源
kubectl apply -f jdk21-runner-serviceaccount.yaml
kubectl apply -f jdk21-runner-rbac.yaml
kubectl apply -f jdk21-runner-configmap.yaml
kubectl apply -f jdk21-runner-statefulset.yaml

# 4. 验证
kubectl get pods -n msa-dev -l app=jdk21-runner
kubectl exec -n msa-dev jdk21-runner-0 -c gitlab-runner -- /usr/local/bin/gitlab-runner verify
```

---

## 详细步骤

### 步骤 1: 构建 Runner 镜像

```bash
cd jdk21-runner

# 确认 .m2 和 .ssh 目录已准备好
ls -la .m2/settings.xml
ls -la .ssh/

# 构建镜像
docker build -f Base_Dockerfile -t harbor-develop.zuzuche.net/middleware/jdk21-runner:1.0 .

# 验证镜像
docker run --rm harbor-develop.zuzuche.net/middleware/jdk21-runner:1.0 java -version
docker run --rm harbor-develop.zuzuche.net/middleware/jdk21-runner:1.0 mvn -version

# 推送到 Harbor
docker push harbor-develop.zuzuche.net/middleware/jdk21-runner:1.0
```

### 步骤 2: 获取 GitLab Registration Token

1. 打开 GitLab 项目或群组
2. 进入 **Settings** → **CI/CD** → **Runners**
3. 展开 "Runners" 部分
4. 复制以下信息：
   - **URL**: `http://git-repositories.zuzuche.com:10081/`
   - **Registration Token**: `glrt-xxxxxxxxxxxxx`

### 步骤 3: 注册 Runner 获取 Runner Token

**⚠️ 重要**: 页面上的 Registration Token **不能**直接写入 ConfigMap，必须先注册获取 Runner Token。

#### 方式 1: 在已部署的 Pod 中注册（推荐）

```bash
# 先用临时配置部署 StatefulSet，让 Pod 启动
kubectl apply -f jdk21-runner-statefulset.yaml -n msa-dev

# 编辑注册脚本
vim scripts/register-runner.sh
# 修改 CI_SERVER_URL 和 REGISTRATION_TOKEN

# 将脚本拷贝到 Pod
kubectl cp scripts/register-runner.sh msa-dev/jdk21-runner-0:/tmp/register.sh -c gitlab-runner

# 在 Pod 中执行
kubectl exec -n msa-dev jdk21-runner-0 -c gitlab-runner -- sh /tmp/register.sh
```

#### 方式 2: 在本机注册（需本机有 gitlab-runner）

```bash
# 编辑并执行脚本
vim scripts/register-runner.sh
bash scripts/register-runner.sh
```

#### 提取 Runner Token

注册成功后，输出中会包含：
```toml
[[runners]]
  name = "jdk21-runner"
  url = "http://git-repositories.zuzuche.com:10081/"
  token = "glrt-xxxxxxxxxxxxxxxxxxxxx"  # ← 这就是 Runner Token
  executor = "shell"
```

**复制这个 token 值**（引号内的整串）。

### 步骤 4: 更新 ConfigMap

编辑 `jdk21-runner-configmap.yaml`，将 `RUNNER_TOKEN_HERE_REPLACE_ME` 替换为上面获取的 Runner Token：

```yaml
[[runners]]
  name = "jdk21-runner-0"
  url = "http://git-repositories.zuzuche.com:10081/"
  token = "glrt-xxxxxxxxxxxxxxxxxxxxx"  # ← 替换为真实的 Runner Token
  executor = "shell"
  tag_list = ["jdk21", "maven", "java21"]
```

### 步骤 5: 部署到 Kubernetes

```bash
# 创建 namespace
kubectl create namespace msa-dev

# 创建 Harbor ImagePullSecret（如果不存在）
kubectl create secret docker-registry harbor-develop-registry-key \
  --docker-server=harbor-develop.zuzuche.net \
  --docker-username=admin \
  --docker-password=your-password \
  -n msa-dev

# 按顺序部署
kubectl apply -f jdk21-runner-serviceaccount.yaml -n msa-dev
kubectl apply -f jdk21-runner-rbac.yaml -n msa-dev
kubectl apply -f jdk21-runner-configmap.yaml -n msa-dev
kubectl apply -f jdk21-runner-statefulset.yaml -n msa-dev

# 重启 StatefulSet（如果之前已部署）
kubectl rollout restart statefulset jdk21-runner -n msa-dev
```

### 步骤 6: 配置 Docker Login（可选）

#### 方式 1: 在 Pod 中临时登录

```bash
# 编辑脚本配置
vim scripts/docker-login-in-pods.sh

# 执行登录
chmod +x scripts/docker-login-in-pods.sh
./scripts/docker-login-in-pods.sh msa-dev
```

#### 方式 2: 在 CI 中登录（推荐）

在 GitLab 项目的 **Settings** → **CI/CD** → **Variables** 中添加：
- `HARBOR_URL`: `harbor-develop.zuzuche.net`
- `HARBOR_USER`: `admin`
- `HARBOR_PASSWORD`: `your-password` (勾选 Masked)

然后在 `.gitlab-ci.yml` 中：
```yaml
before_script:
  - echo "$HARBOR_PASSWORD" | docker login $HARBOR_URL -u "$HARBOR_USER" --password-stdin
```

---

## 验证与测试

### 1. 检查 Pod 状态

```bash
# 查看 Pod
kubectl get pods -n msa-dev -l app=jdk21-runner

# 预期输出
NAME              READY   STATUS    RESTARTS   AGE
jdk21-runner-0    1/1     Running   0          2m
jdk21-runner-1    1/1     Running   0          2m
```

### 2. 验证 Runner 连接

```bash
# 验证 Runner 是否连接到 GitLab
kubectl exec -n msa-dev jdk21-runner-0 -c gitlab-runner -- \
  /usr/local/bin/gitlab-runner verify

# 预期输出
Verifying runner... is alive                        runner=xxxxx
```

**如果出现 `is removed` 或 `403 Forbidden`**：
- Runner Token 已失效或错误
- 需要重新注册并更新 ConfigMap

### 3. 查看 Runner 日志

```bash
# 查看日志
kubectl logs -n msa-dev jdk21-runner-0 -c gitlab-runner --tail=50

# 预期看到
Checking for jobs... received
```

### 4. 查看实际配置

```bash
# 查看 Pod 中的配置文件
kubectl exec -n msa-dev jdk21-runner-0 -c gitlab-runner -- \
  cat /etc/gitlab-runner/config.toml
```

### 5. 测试 JDK 版本

```bash
# 验证 Java 版本
kubectl exec -n msa-dev jdk21-runner-0 -c gitlab-runner -- java -version

# 预期输出
openjdk version "21.0.x" ...
```

### 6. 在 GitLab UI 中验证

打开 **Settings** → **CI/CD** → **Runners**，应该能看到：
- ✅ 绿色圆点，状态为 "online"
- Runner 名称：`jdk21-runner-0`、`jdk21-runner-1`
- 标签：`jdk21`, `maven`, `java21`

---

## CI 配置示例

### 基础 Java 项目构建

```yaml
stages:
  - build
  - test

variables:
  MAVEN_OPTS: "-Dmaven.repo.local=/root/.m2/repository"

build:
  stage: build
  tags:
    - jdk21
  script:
    - java -version
    - /opt/apache-maven-3.9.9/bin/mvn clean package -DskipTests
  artifacts:
    paths:
      - target/*.jar
```

### 使用 JDK 21 新特性

```yaml
jdk21-preview-test:
  stage: test
  tags:
    - jdk21
  script:
    - java --version
    - java --enable-preview --source 21 YourApp.java
```

完整示例参见：`example-gitlab-ci.yml`

---

## 常见问题

### Q1: 构建时找不到 Maven 或 Java？

**原因**: PATH 环境变量配置问题

**解决**:
```yaml
# 方式 1: 使用绝对路径
script:
  - /opt/apache-maven-3.9.9/bin/mvn clean package

# 方式 2: 在 CI 中设置 PATH
before_script:
  - export PATH=/opt/apache-maven-3.9.9/bin:$PATH
  - export JAVA_HOME=/opt/java/openjdk
```

### Q2: Runner Token 失效（403 Forbidden）

**原因**: 
- Runner 在 GitLab 中被删除
- Token 过期或无效

**解决**:
1. 重新执行注册步骤获取新 Token
2. 更新 ConfigMap
3. 重启 StatefulSet

### Q3: Docker build/push 失败

**原因**: 
- 未登录 Harbor
- 宿主机 Docker socket 权限问题

**解决**:
```bash
# 方式 1: 在 Pod 中登录
./scripts/docker-login-in-pods.sh

# 方式 2: 在 CI 中每次登录（推荐）
before_script:
  - echo "$HARBOR_PASSWORD" | docker login $HARBOR_URL -u "$HARBOR_USER" --password-stdin
```

### Q4: Maven 依赖下载慢

**原因**: 未配置镜像源

**解决**: 编辑 `.m2/settings.xml`，添加阿里云或内网 Nexus 镜像：
```xml
<mirror>
  <id>nexus-aliyun</id>
  <mirrorOf>central</mirrorOf>
  <url>https://maven.aliyun.com/repository/public</url>
</mirror>
```

### Q5: 多个 Job 并发冲突

**原因**: ConfigMap 中 `concurrent > 1`

**解决**: 保持 `concurrent = 1`，通过增加 Pod 副本数来提高并发：
```yaml
spec:
  replicas: 4  # 增加到 4 个 Pod
```

### Q6: 构建目录冲突

**原因**: 多个 Runner 使用相同 token

**解决**: 每个 [[runners]] 配置块使用不同的 token（分别注册获得）

### Q7: kubectl 权限不足

**原因**: RBAC 配置不足

**解决**: 根据实际需求编辑 `jdk21-runner-rbac.yaml`，添加必要权限

---

## 更新与维护

### 更新 ConfigMap

```bash
# 修改 ConfigMap
vim jdk21-runner-configmap.yaml

# 应用更改
kubectl apply -f jdk21-runner-configmap.yaml -n msa-dev

# 重启 StatefulSet
kubectl rollout restart statefulset jdk21-runner -n msa-dev
```

### 更新镜像

```bash
# 构建新版本
docker build -f Base_Dockerfile -t harbor-develop.zuzuche.net/middleware/jdk21-runner:1.1 .
docker push harbor-develop.zuzuche.net/middleware/jdk21-runner:1.1

# 更新 StatefulSet
kubectl set image statefulset/jdk21-runner \
  gitlab-runner=harbor-develop.zuzuche.net/middleware/jdk21-runner:1.1 \
  -n msa-dev

# 或者编辑 yaml 后重新 apply
vim jdk21-runner-statefulset.yaml
kubectl apply -f jdk21-runner-statefulset.yaml -n msa-dev
```

### 清理

```bash
# 删除 StatefulSet（保留 PVC）
kubectl delete statefulset jdk21-runner -n msa-dev

# 删除所有资源（包括 PVC）
kubectl delete -f jdk21-runner-statefulset.yaml -n msa-dev
kubectl delete pvc -l app=jdk21-runner -n msa-dev
kubectl delete -f jdk21-runner-configmap.yaml -n msa-dev
kubectl delete -f jdk21-runner-rbac.yaml -n msa-dev
kubectl delete -f jdk21-runner-serviceaccount.yaml -n msa-dev
```

---

## 参考资料

- [GitLab Runner 官方文档](https://docs.gitlab.com/runner/)
- [JDK 21 发行说明](https://openjdk.org/projects/jdk/21/)
- [Maven 3.9 发行说明](https://maven.apache.org/docs/3.9.0/release-notes.html)
- [原始 Wiki 文档](https://wiki.int.zuzuche.info/pages/viewpage.action?pageId=867827713)

---

## 许可与支持

如有问题，请联系 DevOps 团队或在内部 Wiki 上查看更多文档。
