#!/usr/bin/env bash
# =============================================================================
# install-deps.sh — Spring AI Alibaba Admin 本地环境一键安装（跨 OS）
# -----------------------------------------------------------------------------
# 设计说明（为什么中间件走 docker-compose 而非 brew/apt 原生装每个组件）：
#   项目中间件由 docker/middleware/docker-compose-prod.yaml 统一定义，版本固定、
#   且自带初始化容器（MySQL 自动建库建表、ES 自动建索引+pipeline、RocketMQ 自动建 topic）。
#   原生用 brew/apt 装 ES9 / RocketMQ5(namesrv+broker+proxy) / LoongCollector / Nacos 会：
#     1) 版本与项目不一致；2) 缺少 init 容器（需手搓建索引/建 topic）；3) LoongCollector 无 brew/apt 包。
#   因此：用各 OS 的原生包管理器装 **Docker 运行时**（brew/apt/Docker Desktop），
#   再用项目自带 compose 在所有 OS 上以完全一致的方式拉起中间件 + 初始化。
#   详见 docs-research/07-env-checklist.md。
#
# Windows 约定：不装 C 盘；下载与数据一律放 D:\Developer\DeveloperInstall
# =============================================================================
set -euo pipefail

# ---------- 颜色 ----------
C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'
info()  { printf "%s[INFO]%s  %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf "%s[WARN]%s  %s\n"  "$C_YELLOW" "$C_RESET" "$*"; }
err()   { printf "%s[ERROR]%s %s\n" "$C_RED" "$C_RESET" "$*"; }
ok()    { printf "%s[OK]%s    %s\n"  "$C_GREEN" "$C_RESET" "$*"; }

# ---------- 路径 ----------
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"      # -> spring-ai-alibaba-admin
COMPOSE_FILE="$PROJECT_ROOT/docker/middleware/docker-compose-prod.yaml"
WIN_INSTALL_BASE="D:/Developer/DeveloperInstall"       # Windows 安装根（正斜杠给 docker 用）

# ---------- OS 探测 ----------
detect_os() {
  case "$(uname -s)" in
    Darwin*)         echo "mac" ;;
    Linux*)          echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)               echo "unknown" ;;
  esac
}
OS="$(detect_os)"

# =============================================================================
# 1. 工具链：Docker 运行时（+ 可选 JDK/Maven/Node）
# =============================================================================
ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    ok "Docker 已就绪：$(docker --version)"
    return 0
  fi
  warn "未检测到可用的 Docker 运行时。按 OS 安装："
  case "$OS" in
    mac)
      info "macOS: brew install --cask docker  (然后启动 Docker.app)"
      if command -v brew >/dev/null 2>&1; then brew install --cask docker || warn "brew 安装失败，请手动装 Docker Desktop"; else
        err "无 brew。安装: https://brew.sh ; Docker: https://www.docker.com/products/docker-desktop/"; fi ;;
    linux)
      info "Linux(apt): 安装 Docker Engine + compose 插件"
      sudo apt-get update
      sudo apt-get install -y ca-certificates curl gnupg
      sudo install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || true
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list
      sudo apt-get update
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      sudo usermod -aG docker "$USER" || true
      warn "已加入 docker 组，需重新登录或 'newgrp docker' 生效" ;;
    windows)
      info "Windows: 需 Docker Desktop（装到 D 盘）+ WSL2 后端"
      err "  1) 以管理员身份开启 PowerShell，执行:  wsl --install   ; 然后重启"
      err "  2) 下载 Docker Desktop 安装包到 D 盘并安装（自定义路径 $WIN_INSTALL_BASE\\Docker）:"
      err "     curl -L -o '$WIN_INSTALL_BASE/DockerDesktopInstaller.exe' 'https://desktop.docker.com/win/main/amd64/Docker%%20Desktop%%20Installer.exe'"
      err "     （安装时在 Settings > Resources 把 disk image location 设到 D 盘，避免占 C 盘）"
      err "  3) 启动 Docker Desktop 后，重新运行本脚本"
      err "  本会话为非管理员、非交互 shell，无法自动完成 wsl --install / Docker Desktop 安装（需 UAC + 重启）。"
      return 1 ;;
    *) err "未知 OS，请手动安装 Docker: https://docs.docker.com/get-docker/"; return 1 ;;
  esac
  # 安装后复查
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then ok "Docker 现已就绪"; return 0; fi
  err "Docker 仍不可用，请确认 Docker 守护进程已启动"; return 1
}

ensure_toolchain() {
  info "检查工具链（JDK17+ / Maven3.8+ / Node20+）..."
  command -v java >/dev/null 2>&1 && info "Java: $(java -version 2>&1 | head -1)" || warn "缺 JDK17（Temurin 下载: https://adoptium.net/temurin/releases/?version=17）"
  command -v mvn  >/dev/null 2>&1 && info "Maven: $(mvn -v 2>&1 | head -1)" || warn "缺 Maven（下载: https://maven.apache.org/download.cgi）"
  command -v node >/dev/null 2>&1 && info "Node: $(node -v)" || warn "缺 Node20（下载: https://nodejs.org/en/download/）"
}

# =============================================================================
# 2. 中间件：项目 docker-compose（自带 MySQL 建库建表 / ES 建索引 / RocketMQ 建 topic）
# =============================================================================
MW_HOME="$PROJECT_ROOT"   # 默认数据放项目内
bring_up_middleware() {
  local mw_dir="$PROJECT_ROOT/docker/middleware"
  case "$OS" in
    windows)
      MW_HOME="$WIN_INSTALL_BASE/middleware"   # 数据落 D:\Developer\DeveloperInstall（不用 C 盘）
      mkdir -p "$MW_HOME"
      # compose 以 ${MIDDLEWARE_HOME}/{init,conf} 挂载项目的建表 SQL/ES 脚本/中间件配置，
      # 这些静态文件原在项目 docker/middleware 下，需拷到数据同目录才能被正确挂载
      mkdir -p "$MW_HOME/init" "$MW_HOME/conf"
      cp -rf "$mw_dir/init/." "$MW_HOME/init/" 2>/dev/null || true
      cp -rf "$mw_dir/conf/." "$MW_HOME/conf/" 2>/dev/null || true
      # Git 在 Windows checkout 会把 .sh 转成 CRLF，Linux 容器里 sh 解析会报 ": not found"——统一去 CR
      find "$MW_HOME/init" "$MW_HOME/conf" -type f \( -name "*.sh" -o -name "*.cmd" \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true ;;
    *) MW_HOME="$mw_dir" ;;
  esac
  # 生成 .env：rmq_* 服务的 env_file: ./.env 依赖它；且提供 UID/GID/MIDDLEWARE_HOME 变量替换
  local uid gid
  if [ "$OS" = "windows" ]; then uid=1000; gid=1000; else uid=$(id -u); gid=$(id -g); fi
  cat > "$mw_dir/.env" <<EOF
UID=$uid
GID=$gid
TZ=Asia/Shanghai
MIDDLEWARE_HOME=$MW_HOME
EOF
  export MIDDLEWARE_HOME="$MW_HOME"
  local compose_args=(--env-file .env -f docker-compose-prod.yaml)
  if [ "${USE_CN_MIRROR:-1}" = "1" ] && [ -f "$SCRIPT_DIR/docker-compose-mirror.yaml" ]; then
    compose_args+=(-f "$SCRIPT_DIR/docker-compose-mirror.yaml")
    info "启用国内镜像 override（docker.io → docker.m.daocloud.io；USE_CN_MIRROR=0 可关）"
  fi
  info "拉起中间件（prod 全集），数据目录: $MIDDLEWARE_HOME（UID/GID=$uid/$gid）"
  ( cd "$mw_dir" && docker compose "${compose_args[@]}" up -d --build )
  info "等待服务健康（init 容器建索引/建 topic 需 ~60-90s）..."
  sleep 30
}

# =============================================================================
# 3. 初始化（compose 已含；这里做幂等补充与确认）
# =============================================================================
init_mysql_confirm() {
  info "[MySQL] 确认 admin 库与表已建"
  docker exec mysql mysql -uroot -proot -e "CREATE DATABASE IF NOT EXISTS admin DEFAULT CHARSET utf8mb4;" 2>/dev/null || true
  local tables
  tables=$(docker exec mysql mysql -uadmin -padmin -D admin -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='admin';" 2>/dev/null || echo 0)
  if [ "${tables:-0}" -ge 20 ]; then ok "admin 库表数=$tables（已加载 agentscope+admin 两份 schema）"; else warn "admin 库表数=$tables，偏少；若非首启可能正常，否则检查 init/mysql/*.sql"; fi
}
init_es_confirm() {
  info "[Elasticsearch] 确认 loongsuite_traces 索引 + pipeline"
  curl -fs http://localhost:9200/_ingest/pipeline/parsing_loongsuite_traces >/dev/null 2>&1 && ok "pipeline parsing_loongsuite_traces 存在" || warn "pipeline 缺失（elasticsearch-init 可能仍在跑）"
  curl -fs http://localhost:9200/loongsuite_traces/_mapping >/dev/null 2>&1 && ok "索引 loongsuite_traces 存在" || warn "索引缺失（elasticsearch-init 可能仍在跑）"
}
init_rocketmq_confirm() {
  info "[RocketMQ] 确认 topic 已建"
  if docker exec rmq_namesrv sh mqadmin topicList -n rmq_namesrv:9876 2>/dev/null | grep -q "topic_saa_studio_document_index"; then
    ok "topic topic_saa_studio_document_index 已建"
  else warn "topic 未就绪（rmq-init-topic 容器需 ~60s 等待 broker）"; fi
}

# =============================================================================
# 4. 验证（逐项端口/健康）
# =============================================================================
verify_all() {
  info "==== 逐项验证 ===="
  docker exec mysql mysqladmin -uadmin -padmin ping >/dev/null 2>&1 && ok "MySQL :3306  ping=PONG" || err "MySQL 不通"
  docker exec redis redis-cli ping 2>/dev/null | grep -q PONG && ok "Redis  :6379  ping=PONG" || err "Redis 不通"
  curl -fs http://localhost:9200/_cluster/health >/dev/null 2>&1 && ok "ES     :9200  集群健康" || err "ES 不通"
  curl -fs http://localhost:5601 >/dev/null 2>&1 && ok "Kibana :5601  可访问" || warn "Kibana :5601 未就绪（可选）"
  curl -fs "http://localhost:7080/nacos/" >/dev/null 2>&1 && ok "Nacos  :7080  控制台可访问" || warn "Nacos 控制台未就绪（应用用 :8848 gRPC）"
  curl -fs http://localhost:4318/ >/dev/null 2>&1 && ok "OTLP   :4318  LoongCollector 监听" || warn "OTLP :4318 端口未开（LoongCollector 启动较慢）"
  info "应用侧连接：nacos.server-addr=localhost:8848（gRPC）/ rocketmq.endpoints=localhost:18080（proxy）/ otlp=localhost:4318"
}

# =============================================================================
# main
# =============================================================================
main() {
  info "OS=$OS   PROJECT_ROOT=$PROJECT_ROOT"
  ensure_toolchain
  ensure_docker || { err "Docker 不可用，无法继续拉起中间件。请先解决 Docker（见上方提示）。"; exit 2; }
  bring_up_middleware
  init_mysql_confirm
  init_es_confirm
  init_rocketmq_confirm
  verify_all
  info "==== 完成 ===="
  echo "  中间件数据目录: $MIDDLEWARE_HOME"
  echo "  下一步: 配 model-config.yaml + API Key；后端 mvn spring-boot:run（本地建议 -Dspring.profiles.active=local）；前端 npm run dev"
}

main "$@"
