#!/bin/bash
# ==========================================
# 酷狗概念版 Cookie 自动刷新脚本 (恢复版)
# ==========================================

API_URL="http://127.0.0.1:3001"
H_FILE="/volume2/dev/data/api-secrets/musicAPI/kugou_cookie_header.txt"
J_FILE="/volume2/dev/data/api-secrets/musicAPI/kugou_token.json"
T_FILE="/volume2/dev/data/api-secrets/musicAPI/kugou_token.txt"
LOG="/volume2/dev/shell/logs/kugou_refresh.log"

now() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(now)] $1" >> "$LOG"; }

# 1. 检测基础 Header 文件是否存在
if [ ! -f "$H_FILE" ]; then
    log "ERROR: 找不到 $H_FILE，请确保该文件内有你手动测试成功的旧 Cookie。"
    exit 1
fi

# 2. 读取并彻底清洗当前 Cookie (物理擦除换行符和空格)
RAW_C=$(cat "$H_FILE" | tr -d '\r\n ')

# 3. 发起刷新请求 (使用最稳妥的 URL 参数传递模式)
RESP=$(curl -s "${API_URL}/login/token?cookie=${RAW_C}")
STATUS=$(echo "$RESP" | grep -o "\"status\":[0-9]*" | head -1 | cut -d: -f2)

if [ "$STATUS" = "1" ]; then
    # 4. 提取新返回的 Token 和 t1
    N_TK=$(echo "$RESP" | grep -o "\"token\": *\"[^\"]*\"" | head -1 | cut -d"\"" -f4)
    N_T1=$(echo "$RESP" | grep -o "\"t1\": *\"[^\"]*\"" | head -1 | cut -d"\"" -f4)
    
    # 5. 从旧 Cookie 中提取不变的身份参数
    get_p() { echo "$RAW_C" | grep -o "$1=[^;]*" | cut -d= -f2; }
    U_ID=$(get_p "userid")
    D_ID=$(get_p "dfid")

    # 6. 重新组装标准格式 (无空格，核心三项及刷新所需的t1)
    NEW_C="token=${N_TK};userid=${U_ID};dfid=${D_ID};t1=${N_T1};vip_token=;vip_type=0;KUGOU_API_PLATFORM=lite"

    # 7. 同步写回所有依赖文件
    # 写回 Header 文件
    echo -n "$NEW_C" > "$H_FILE"
    
    # 写回 JSON 文件 (供领取 VIP 脚本读取)
    # 如果 JSON 损坏或不存在，先初始化它
    if [ ! -f "$J_FILE" ] || [ ! -s "$J_FILE" ]; then
        echo "{\"token\":\"$N_TK\",\"userid\":\"$U_ID\",\"dfid\":\"$D_ID\",\"t1\":\"$N_T1\",\"update_time\":\"$(now)\"}" > "$J_FILE"
    else
        sed -i "s|\"token\": *\"[^\"]*\"|\"token\": \"${N_TK}\"|" "$J_FILE"
        sed -i "s|\"t1\": *\"[^\"]*\"|\"t1\": \"${N_T1}\"|" "$J_FILE"
        sed -i "s|\"update_time\": *\".*\"|\"update_time\": \"$(now)\"|" "$J_FILE"
    fi

    # 写回 Netscape TXT 文件
    echo "# Netscape HTTP Cookie File" > "$T_FILE"
    echo "$NEW_C" | tr ";" "\n" | while read -r l; do
        [ -n "$l" ] && echo -e "127.0.0.1\tFALSE\t/\tFALSE\t0\t${l%%=*}\t${l#*=}" >> "$T_FILE"
    done

    log "SUCCESS: Token 刷新成功，所有 Cookie 文件已完成同步。"
else
    ERR_CODE=$(echo "$RESP" | grep -o "\"error_code\":[0-9]*" | head -1 | cut -d: -f2)
    log "ERROR: 刷新失败。错误码: $ERR_CODE。API返回: $RESP"
fi
