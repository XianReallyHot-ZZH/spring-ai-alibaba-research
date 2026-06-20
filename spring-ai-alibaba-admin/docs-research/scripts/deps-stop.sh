#!/usr/bin/env bash
# deps-stop.sh — 一键停止所有依赖中间件（保留数据卷/数据目录，下次 start 复用）。
set -uo pipefail

C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'
info(){ printf "%s[INFO]%s %s\n" "$C_GREEN" "$C_RESET" "$*"; }
ok(){ printf "%s[OK]%s    %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn(){ printf "%s[WARN]%s  %s\n" "$C_YELLOW" "$C_RESET" "$*"; }

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
MW_DIR="$PROJECT_ROOT/docker/middleware"
OVR="$SCRIPT_DIR/docker-compose-mirror.yaml"

[ -f "$MW_DIR/.env" ] || { warn "缺 .env（可能尚未安装）；仅按 compose 文件停止。"; }

COMPOSE=(docker compose --env-file .env -f docker-compose-prod.yaml)
[ -f "$OVR" ] && COMPOSE+=(-f "$OVR")

docker info >/dev/null 2>&1 || { warn "Docker 未运行，无需停止。"; exit 0; }

info "停止中间件（compose down，保留数据卷）..."
( cd "$MW_DIR" && "${COMPOSE[@]}" down 2>&1 | grep -vE "Downloading|Pulling" || true )

# 确认
remaining=$(docker ps -a --filter "label=com.docker.compose.project=middleware" --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
if [ "${remaining:-0}" -eq 0 ]; then
  ok "全部中间件已停止（数据保留，下次 deps-start.sh 复用）。"
else
  warn "仍有 $remaining 个容器残留：docker ps -a 查看。"
fi
