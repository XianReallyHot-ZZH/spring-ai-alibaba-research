#!/usr/bin/env bash
# deps-status.sh — 查看每个中间件的运行状态 + 端口监听情况。
set -uo pipefail

C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'

# 服务清单：name|container|host_port
SVCS=(
  "MySQL|mysql|3306"
  "Redis|redis|6379"
  "Elasticsearch|elasticsearch|9200"
  "Kibana|kibana|5601"
  "LoongCollector(OTLP)|loongcollector|4318"
  "Nacos|nacos|8848"
  "RocketMQ namesrv|rmq_namesrv|9876"
  "RocketMQ broker|rmq_broker|10911"
  "RocketMQ proxy|rmq_proxy|18080"
)

docker info >/dev/null 2>&1 || { printf "%sDocker 未运行%s\n" "$C_RED" "$C_RESET"; exit 1; }

cstat(){ # container -> Up(healthy)/Up/Exited/absent
  local c="$1" s
  s=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null) || { printf "%sabsent%s" "$C_DIM" "$C_RESET"; return; }
  case "$s" in
    running) if docker inspect -f '{{json .State.Health.Status}}' "$c" 2>/dev/null | grep -q healthy; then
               printf "%sUp (healthy)%s" "$C_GREEN" "$C_RESET"; else printf "%sUp%s" "$C_GREEN" "$C_RESET"; fi ;;
    exited|dead) printf "%s%s%s" "$C_RED" "$s" "$C_RESET" ;;
    restarting) printf "%s%s%s" "$C_YELLOW" "$s" "$C_RESET" ;;
    *) printf "%s%s" "$C_YELLOW" "$s" "$C_RESET";;
  esac
}

listening(){ # port -> yes/no（netstat 优先，ss 兜底）
  local p="$1"
  { netstat -ano 2>/dev/null | grep -E "[:.]$p\s" | grep -iq LISTENING; } \
    || { ss -ltn 2>/dev/null | grep -Eq ":$p\s"; }
}

printf "%-22s %-20s %-12s %s\n" "中间件" "容器状态" "宿主端口" "监听"
printf "%-22s %-20s %-12s %s\n" "---------------------" "----------" "-------" "----"
down=0
for row in "${SVCS[@]}"; do
  IFS='|' read -r name ctr port <<<"$row"
  st=$(cstat "$ctr")
  if listening "$port"; then lp="${C_GREEN}yes${C_RESET}"; else lp="${C_RED}no${C_RESET}"; fi
  printf "%-22s %-28s %-12s %b\n" "$name" "$st" ":$port" "$lp"
  docker inspect -f '{{.State.Status}}' "$ctr" 2>/dev/null | grep -qi running || down=$((down+1))
done

# 快速健康抽检（便宜的几项）
echo ""
printf "%s快速健康抽检：%s\n" "$C_DIM" "$C_RESET"
chk(){ printf "  %-26s " "$1"; shift; if "$@" >/dev/null 2>&1; then printf "%s✅%s\n" "$C_GREEN" "$C_RESET"; else printf "%s❌%s\n" "$C_RED" "$C_RESET"; fi; }
chk "MySQL ping (admin/admin)" docker exec mysql mysqladmin -uadmin -padmin ping
chk "Redis PING"               docker exec redis redis-cli ping
chk "ES cluster health"        curl -sf --retry 3 --retry-connrefused --max-time 5 http://localhost:9200/_cluster/health
chk "ES loongsuite_traces"     curl -sf --retry 3 --retry-connrefused --max-time 5 http://localhost:9200/loongsuite_traces/_mapping
chk "RocketMQ topic 存在"      sh -c 'docker exec rmq_namesrv sh mqadmin topicList -n rmq_namesrv:9876 2>/dev/null | grep -q topic_saa_studio_document_index'
chk "MySQL admin 库表数≥20"     sh -c 'n=$(docker exec mysql mysql -uadmin -padmin -D admin -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"admin\";" 2>/dev/null); [ "${n:-0}" -ge 20 ]'

echo ""
total=${#SVCS[@]}; up=$((total-down))
printf "汇总：%s%d/%d%s 个容器在运行\n" "$C_GREEN" "$up" "$total" "$C_RESET"
