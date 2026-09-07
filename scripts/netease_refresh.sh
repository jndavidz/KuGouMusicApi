#!/bin/bash

API_URL="http://10.10.10.2:3000"
COOKIE_FILE="/volume2/dev/data/api-secrets/musicAPI/netease_cookie.txt"
BACKUP_DIR="/volume2/dev/data/api-secrets/backup"
LOG_FILE="/volume2/dev/shell/logs/netease_refresh.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

if [ ! -f "$COOKIE_FILE" ]; then
    log "错误: Cookie 文件不存在 -> $COOKIE_FILE"
    exit 1
fi

# 1. 提取或读取当前纯净的 MUSIC_U
# 即使文件里不小心混入了别的，这里也只拿 MUSIC_U 发送请求
CURRENT_COOKIE=$(grep -o 'MUSIC_U=[^;]*' "$COOKIE_FILE" | head -1)

if [ -z "$CURRENT_COOKIE" ]; then
    log "错误: 无法从文件中解析出有效的 MUSIC_U 字段，请检查文件内容。"
    exit 1
fi

# 1.5 刷新前备份当前 Cookie（时间戳命名；目录在 Drive 同步区，自动镜像至 PC D:\dev\data\api-secrets\backup）
mkdir -p "$BACKUP_DIR"
BAK_FILE="$BACKUP_DIR/netease_cookie.txt.bak-$(date +%Y%m%d-%H%M%S)"
cp -p "$COOKIE_FILE" "$BAK_FILE" && log "已备份当前 Cookie -> $BAK_FILE"

# 2. 调用刷新接口 (-i 同时拿到 Header，因为新 Cookie 经常在 Header 的 Set-Cookie 里)
RESPONSE=$(curl -s -i -X GET "$API_URL/login/refresh?cookie=${CURRENT_COOKIE}&timestamp=$(date +%s)")

# 3. 验证接口是否响应成功
if echo "$RESPONSE" | grep -q '"code":200' || echo "$RESPONSE" | grep -q -i "200 OK"; then

    # 4. 精准提取：不管是返回的 JSON 体还是 Header，只抠出 MUSIC_U=xxxx 这一段
    NEW_COOKIE=$(echo "$RESPONSE" | grep -o 'MUSIC_U=[^;]*' | head -1)

    if [ -n "$NEW_COOKIE" ]; then
        # 5. 写入文件（格式保持为标准的：MUSIC_U=xxxx）
        echo "$NEW_COOKIE" > "$COOKIE_FILE"
        log "Cookie 刷新成功，已写入纯净的 MUSIC_U 字段。"
    else
        log "接口返回 200，但未能从响应体或 Header 中提取到新 MUSIC_U 字段。"
    fi
else
    # 发生错误时把响应打印到 log，方便排查
    log "Cookie 刷新失败，请检查 API 状态。接口响应快照: $(echo "$RESPONSE" | tail -n 3)"
fi
