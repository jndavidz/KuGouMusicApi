#!/bin/bash
# ==========================================
# 酷狗概念版 VIP 自动领取及升级脚本 (精简版)
# ==========================================

API_URL="http://127.0.0.1:3001"
TOKEN_FILE="/volume2/dev/data/api-secrets/musicAPI/kugou_token.json"
LOG_FILE="/volume2/dev/shell/logs/kugou_vip.log"
BARK_URL=""

now() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(now)] $1" >> "$LOG_FILE"; echo "[$(now)] $1"; }

# 1. 提取三项核心凭证
if [ ! -f "$TOKEN_FILE" ]; then
    log "ERROR: 找不到配置文件 $TOKEN_FILE"
    exit 1
fi

# 使用 tr 处理可能的不可见字符，确保变量纯净
TOKEN=$(grep -o '"token": *"[^"]*"' "$TOKEN_FILE" | head -1 | cut -d'"' -f4 | tr -d '\r\n ')
USERID=$(grep -o '"userid": *"[^"]*"' "$TOKEN_FILE" | head -1 | cut -d'"' -f4 | tr -d '\r\n ')
DFID=$(grep -o '"dfid": *"[^"]*"' "$TOKEN_FILE" | head -1 | cut -d'"' -f4 | tr -d '\r\n ')

if [ -z "$TOKEN" ] || [ -z "$USERID" ]; then
    log "ERROR: 核心凭证读取失败，请检查 kugou_token.json"
    exit 1
fi

# 2. 组装三项核心 Cookie (严格遵循 token;userid;dfid 格式)
COOKIE="token=${TOKEN};userid=${USERID};dfid=${DFID}"

CURRENT_DATE=$(date '+%Y-%m-%d')
# 仅取 "当前年月" 前缀，避免把历史月份的签到记录也数进本月统计
CURRENT_MONTH=$(date '+%Y-%m')

log "======================================="
log "开始执行概念版 VIP 领取流程 (核心模式)"

# 3. 步骤 1: 领取当天畅听 VIP
log "INFO: 步骤 1/2 - 尝试领取 ${CURRENT_DATE} 的畅听 VIP..."
RECEIVE_RESP=$(curl -s "${API_URL}/youth/day/vip?receive_day=${CURRENT_DATE}&cookie=${COOKIE}")
RECEIVE_STATUS=$(echo "$RECEIVE_RESP" | grep -o '"status":[0-9]*' | head -1 | cut -d: -f2)
RECEIVE_ERR=$(echo "$RECEIVE_RESP" | grep -o '"error_code":[0-9]*' | head -1 | cut -d: -f2)

if [ "$RECEIVE_STATUS" = "1" ]; then
    log "✅ OK: 畅听 VIP 领取成功！"
elif [ "$RECEIVE_ERR" = "131001" ]; then
    log "ℹ️ INFO: 今日已领取过畅听 VIP。"
else
    log "⚠️ WARN: 畅听 VIP 领取失败 (error_code: ${RECEIVE_ERR})"
fi

# 4. 延时 5 分钟
log "等待 5 分钟后进行等级升级..."
sleep 300

# 5. 步骤 2: 升级概念版 VIP
log "INFO: 步骤 2/2 - 尝试升级概念版 VIP..."
UPGRADE_RESP=$(curl -s "${API_URL}/youth/day/vip/upgrade?cookie=${COOKIE}")
UPGRADE_STATUS=$(echo "$UPGRADE_RESP" | grep -o '"status":[0-9]*' | head -1 | cut -d: -f2)
UPGRADE_ERR=$(echo "$UPGRADE_RESP" | grep -o '"error_code":[0-9]*' | head -1 | cut -d: -f2)

if [ "$UPGRADE_STATUS" = "1" ]; then
    log "✅ OK: 升级概念版 VIP 成功！"
elif [ "$UPGRADE_ERR" = "297002" ]; then
    log "ℹ️ INFO: 已经领取过升级奖励。"
else
    log "⚠️ WARN: 升级失败 (error_code: ${UPGRADE_ERR})"
fi

# 6. 查询汇总报告
RECORD_RESP=$(curl -s "${API_URL}/youth/month/vip/record?cookie=${COOKIE}")
UNION_RESP=$(curl -s "${API_URL}/youth/union/vip?cookie=${COOKIE}")

COUNT=$(echo "$RECORD_RESP" | grep -o '"day":"[^"]*"' | grep -c "${CURRENT_MONTH}-" 2>/dev/null || echo 0)
SVIP_END=$(echo "$UNION_RESP" | grep -o '"product_type":"svip"[^}]*"vip_end_time":"[^"]*"' | grep -o '"vip_end_time":"[^"]*"' | cut -d'"' -f4)
TVIP_END=$(echo "$UNION_RESP" | grep -o '"product_type":"tvip"[^}]*"vip_end_time":"[^"]*"' | grep -o '"vip_end_time":"[^"]*"' | cut -d'"' -f4)

log "======================================="
log "📊 权益报告"
log "📅 本月已领取: ${COUNT} 天"
[ -n "$SVIP_END" ] && log "🟡 概念超级VIP (svip) 有效期延长至: ${SVIP_END}"
[ -n "$TVIP_END" ] && log "🟢 概念畅听VIP (tvip) 有效期延长至: ${TVIP_END}"
log "======================================="