#!/bin/bash
# deploy.sh — PC 端执行（Git Bash）
# 一条命令完成: PC 源码 → NAS 构建上下文 → Docker 构建 → 容器运行
#
# 前置条件:
#   - SSH 密钥免密登录 zxsadmin@10.10.10.2（已配置）
#   - NAS 上 docker compose 可用（Container Manager）
#   - [可选] PC 装有 pnpm（与 NAS 版本一致），否则 lockfile 校验自动跳过
#
# 使用: ./deploy.sh
set -euo pipefail

cd /d/repos/kugou_api

# ── [1/3] 校验 pnpm-lock.yaml 与 package.json 一致性（可选）──
# merge 上游后若 package.json 变更但 lockfile 未同步, NAS 构建会因
# --frozen-lockfile 直接失败。本步在 PC 上先拦截, 避免白跑一次传输+构建。
# --frozen-lockfile --lockfile-only 组合是纯校验: 一致则通过且不改文件, 不一致则报错。
if command -v pnpm >/dev/null 2>&1; then
  PNPM="pnpm"
elif command -v corepack >/dev/null 2>&1; then
  PNPM="corepack pnpm"
else
  PNPM=""
fi
if [ -n "$PNPM" ]; then
  echo ">>> [1/3] 校验 lockfile 一致性 ..."
  $PNPM install --frozen-lockfile --lockfile-only
  echo "    OK: package.json 与 pnpm-lock.yaml 一致"
else
  echo "!!! [1/3] 未检测到 pnpm/corepack, 跳过 lockfile 校验"
  echo "!!!       若 package.json 变更过, 请先在 PC 执行: pnpm install --lockfile-only"
fi

# ── [2/3] 打包并传输构建上下文 ──
# 排除: git 历史 / ZCode 会话 / node_modules / 敏感凭证(cookies.txt .env .env.example)
# rm -rf 先清空 NAS 部署目录 → 保证 NAS 目录与 PC 仓库精确镜像(无残留模块)
# chmod 644 幂等修复凭证 ACL（防止 Drive 同步重置权限导致容器内 .env 变 000）
echo ">>> [2/3] 传输构建上下文并构建容器 ..."
tar --exclude=.git --exclude=.zcode --exclude=node_modules \
    --exclude=cookies.txt --exclude=.env --exclude=.env.example \
    -cf - . | \
  ssh -o BatchMode=yes zxsadmin@10.10.10.2 \
    'set -e; \
     chmod 644 /volume2/dev/data/api-secrets/kugou_api.env; \
     rm -rf /volume2/docker/kugou_api && mkdir -p /volume2/docker/kugou_api && \
     tar -xf - -C /volume2/docker/kugou_api && \
     cd /volume2/docker/kugou_api && /usr/local/bin/docker compose up -d --build'

# ── [3/3] 验证服务与凭证链路 ──
echo ">>> [3/3] 验证服务与凭证链路 ..."
sleep 2
curl -s -o /dev/null -w "    http://10.10.10.2:3001/ -> HTTP %{http_code}\n" --max-time 5 http://10.10.10.2:3001/
CK=$(cat /d/dev/data/api-secrets/kugou_cookie_header.txt | tr -d '\r\n ')
T1=$(curl -s --max-time 10 "http://10.10.10.2:3001/login/token?cookie=${CK}" | grep -o '"t1":"[^"]*"' | head -1)
if [ -n "$T1" ]; then
  echo "    /login/token -> OK (凭证链路生效)"
else
  echo "    /login/token -> 失败! 检查凭证/设备身份" >&2
  exit 1
fi
echo ">>> 部署完成"
