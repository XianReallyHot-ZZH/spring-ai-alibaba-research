#!/usr/bin/env bash
# deps-start.sh — 一键启动所有依赖中间件，并【等到全部就绪】后再返回（非"刚启动"）。
# 复用 install-deps.sh 装好的 compose 栈（docker-compose-prod.yaml + docker-compose-mirror.yaml + .env）。
set -uo pipefail

C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
info(){ printf "%s[INFO]%s %s\n" "$C_GREEN" "$C_RESET" "$*"; }
ok(){ printf "%s[OK]%s    %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn(){ printf "%s[WARN]%s  %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err(){ printf "%s[ERROR]%s %s\n" "$C_RED" "$C_RESET" "$*"; }

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
MW_DIR="$PROJECT_ROOT/docker/middleware"
OVR="$SCRIPT_DIR/docker-compose-mirror.yaml"

[ -f "$MW_DIR/.env" ] || { err "缺 $MW_DIR/.env —— 请先跑 install-deps.sh 完成安装"; exit 1; }
docker info >/dev/null 2>&1 || { err "Docker 未运行，请先启动 Docker"; exit 1; }

COMPOSE=(docker compose --env-file .env -f docker-compose-prod.yaml)
[ -f "$OVR" ] && COMPOSE+=(-f "$OVR")

info "启动中间件（compose up -d）..."
( cd "$MW_DIR" && "${COMPOSE[@]}" up -d 2>&1 | grep -vE "Downloading|Pulling fs|Already exists|Download complete" || true )
# warm restart 时 elasticsearch-init 会因索引已存在而 exit(非幂等)，连带 loongcollector 不起——
# 索引持久在卷里、无需重跑 init，故 --no-deps 强起 loongcollector
( cd "$MW_DIR" && "${COMPOSE[@]}" up -d --no-deps loongcollector >/dev/null 2>&1 || true )

# ---------- 就绪轮询 ----------
wait_for(){ # name check_cmd [timeout_s]
  local name="$1" check="$2" to="${3:-120}" t=0
  printf "  等待 %-13s " "$name"
  while ! eval "$check" >/dev/null 2>&1; do
    sleep 3; t=$((t+3))
    [ "$t" -ge "$to" ] && { printf "%s❌ 超时(%ss)%s\n" "$C_RED" "$to" "$C_RESET"; return 1; }
  done
  printf "%s✅ 就绪(%ss)%s\n" "$C_GREEN" "$t" "$C_RESET"; return 0
}

info "等待各服务就绪..."
fails=0
wait_for "MySQL"        'docker exec mysql mysqladmin -uadmin -padmin ping 2>/dev/null | grep -qi alive'        90   || fails=$((fails+1))
wait_for "Redis"        'docker exec redis redis-cli ping 2>/dev/null | grep -qi pong'                          30   || fails=$((fails+1))
wait_for "Elasticsearch" 'curl -sf http://localhost:9200/_cluster/health >/dev/null'                            120  || fails=$((fails+1))
wait_for "Kibana"       'curl -sf http://localhost:5601/api/status >/dev/null'                                  120  || fails=$((fails+1))
wait_for "Nacos"        'docker logs nacos 2>&1 | grep -q "started successfully"'                              120  || fails=$((fails+1))
wait_for "RocketMQ"     'docker exec rmq_namesrv sh mqadmin clusterList -n rmq_namesrv:9876 >/dev/null 2>&1'    120  || fails=$((fails+1))
wait_for "OTLP(LoongC)" 'curl -s -o /dev/null -w "%{http_code}" http://localhost:4318/ | grep -qvE "^(000)$"'   60   || fails=$((fails+1))

echo ""
if [ "$fails" -eq 0 ]; then ok "全部中间件就绪。"; exit 0
else err "$fails 个服务未就绪——用 deps-status.sh 查看详情。"; exit 1; fi
