# kugou-api NAS 部署指南

> NAS：群晖 DS416play（DSM 7.3.2，x86_64）。运行形态：Docker 容器（曾对比过 PM2，结论维持 Docker，见 git 历史）。

## 1. 架构与路径权威表

| 角色 | 位置 | 说明 |
|---|---|---|
| 代码唯一源头 | PC `D:\_work\repos\kugou_api`（git，zxs 分支） | 开发、merge 上游、版本管理都在这里 |
| NAS 部署副本 | `/volume2/docker/kugou_api` | docker build 输入（构建上下文），**非 Drive 同步区**，不含凭证 |
| 凭证权威位置 | `/volume2/dev/data/api-secrets/musicAPI/` | Drive 双向同步 ↔ PC `D:\_work\dev\data\api-secrets\musicAPI\`；容器以 `:ro` 挂载其中的 `kugou_api.env` |
| 定时脚本 | 仓库 `scripts/`（权威源）；NAS 运行副本 `/volume2/dev/shell/bin/` | DSM 任务计划调用的是运行副本 |

**凭证文件清单**（均在 `musicAPI/` 下）：

| 文件 | 用途 | 写方 | 读方 |
|---|---|---|---|
| `kugou_api.env` | 容器 `/app/.env`（设备身份、platform） | 手动维护 | 容器 |
| `kugou_cookie_header.txt` | 登录态 Cookie 种子 | `kugou_refresh.sh` 写回 | `kugou_refresh.sh` |
| `kugou_token.json` | 三项核心凭证（token/userid/dfid/t1） | `kugou_refresh.sh` 写回 | `kugou_vip.sh` |
| `kugou_token.txt` | Netscape 格式副本 | `kugou_refresh.sh` 写回 | 备用 |
| `netease_cookie.txt` | 网易云 Cookie | `netease_refresh.sh`（每周五 08:25；刷新前自动备份到 backup/） | netease 脚本（已入库 scripts/） |

> ⚠️ **定时脚本双副本**：`deploy.sh` 只覆盖 `/volume2/docker/kugou_api/scripts/`，**不会**更新 `/volume2/dev/shell/bin/` 运行副本。改了 `scripts/*.sh` 必须手动同步运行副本（`scp -O` 覆盖），否则 DSM 计划任务跑的还是旧逻辑。
> ⚠️ 代码勿放 `/volume2/dev`（Drive 同步根会镜像回 PC）；NAS 部署目录由 `deploy.sh` 每次 `rm -rf` 清空重建。

## 2. 环境需求（NAS 侧）

| 项 | 值 |
|---|---|
| 系统 | DSM 7.3.2-86009 |
| Docker | 24.0.2（`/usr/local/bin/docker`，不在 PATH，用全路径），compose v2.20.1 |
| 权限 | `zxsadmin` 在 docker 组，免 sudo |
| 磁盘 | 镜像 ~400MB，合计 <2GB |

## 3. 构建与部署

### 路线 A：deploy.sh（NAS 构建）

```bash
# PC 端（Git Bash）
cd /d/repos/kugou_api && ./deploy.sh
```

内部流程：lockfile 校验（`--frozen-lockfile --lockfile-only` 不一致即中止）→ tar 传输（排除 `.git`/`node_modules`/凭证）→ NAS 上 `chmod 644` 凭证 + 清空部署目录 + 解压 + `docker compose up -d --build` → 验证 3001 端口与 `/login/token` 链路。

适用：NAS 构建慢（N3060 双核），适合小改动或无 PC 侧 docker 时的兜底。

### 路线 B：WSL 构建直传（推荐）

WSL 与 NAS 同为 x86_64，镜像直接可用；构建快、不给 NAS 施压。

```bash
# 1. WSL 仓库根构建（buildx activity 权限异常时加 DOCKER_BUILDKIT=0）
DOCKER_BUILDKIT=0 docker build -t kugou-api:latest .

# 2. 流式传输并 load（不落盘中间文件，384MB 镜像秒级~十秒级）
docker save kugou-api:latest | gzip | \
  ssh zxsadmin@10.10.10.2 '/usr/local/bin/docker load'

# 3. NAS 用新镜像 + 新 compose 重建容器
ssh zxsadmin@10.10.10.2 'cd /volume2/docker/kugou_api && /usr/local/bin/docker compose up -d --no-build'
```

**收尾必做**（Drive 同步可能重置 ACL，容器内 `.env` 变 `000`）：

```bash
ssh zxsadmin@10.10.10.2 'chmod 644 /volume2/dev/data/api-secrets/musicAPI/kugou_api.env && /usr/local/bin/docker restart kugou-api'
```

**验证**：`curl http://10.10.10.2:3001/` 期望 200；`/login/token?cookie=<header 文件内容>` 返回 `t1` 即凭证链路生效。

> NAS 的 SFTP 子系统不可用（chroot 限制），scp 必须带 `-O` 走传统协议。

## 4. VIP 自动领取与 Cookie 刷新链路

DSM 任务计划（root）每日调度，脚本调 `127.0.0.1:3001`：

| 时间 | 脚本 | 动作 |
|---|---|---|
| 08:30 | `kugou_refresh.sh` | 用旧 Cookie 调 `/login/token` 刷新，写回三个凭证文件 |
| 08:40 | `kugou_vip.sh` | 领取当日畅听 VIP（`/youth/day/vip`）→ 等 5 分钟 → 升级（`/youth/day/vip/upgrade`）→ 查询月记录与权益报告 |
| **每周五** 08:25 | `netease_refresh.sh` | 调 ncm-api `/login/refresh` 刷新网易云 Cookie；**每次刷新前自动备份**当前文件到 `/volume2/dev/data/api-secrets/backup/`（时间戳命名，Drive 同步 ↔ PC `D:\_work\dev\data\api-secrets\backup\`） |

日志：`/volume2/dev/shell/logs/kugou_refresh.log`、`kugou_vip.log`。

**error_code 语义**：

| code | 含义 |
|---|---|
| 131001 | 今日畅听 VIP 已领取过（正常） |
| 297002 | 今日升级奖励已领取过（正常） |
| 20010 | 请求参数无效（检查 Cookie 组装格式：`token;userid;dfid` 核心三项） |
| 空响应/空 code | 酷狗接口异常，当天漏领，次日自动继续 |

## 5. 已知坑速查

| # | 现象 | 处理 |
|---|---|---|
| 1 | 容器启动报 `Bind mount failed` | compose 挂载源（`docker-compose.yml` volumes）指向的凭证文件不存在——核对 `musicAPI/` 路径 |
| 2 | 服务起了但登录态失效，容器内 `/app/.env` 权限 `000` | `chmod 644 .../musicAPI/kugou_api.env && docker restart kugou-api`（路线 A 的 deploy.sh 已内置幂等 chmod） |
| 3 | 定时脚本报 `找不到 kugou_token.json` / `找不到 kugou_cookie_header.txt` | `/volume2/dev/shell/bin/` 运行副本路径过期，从仓库 `scripts/` 同步（scp -O） |
| 4 | Container Manager UI 报"容器undefined不存在"或显示旧状态 | CLI 重建容器后 UI 缓存失步：套件中心重启 Container Manager 即同步；确认实际状态用 `docker ps` |
| 5 | WSL `docker build` 报 buildx activity permission denied | `DOCKER_BUILDKIT=0 docker build ...` 走传统 builder |
| 6 | `scp` 报 `No such file or directory` | NAS SFTP 子系统不可用，加 `-O` |
| 7 | compose 改了但镜像不更新 | compose 必须含 `build:` 段（现文件已有）；`up -d` 默认不重建镜像，代码变更走路线 A `--build` 或路线 B 重传 |
| 8 | `npm install -g pnpm` EEXIST | corepack 占用 shim，加 `--force`（Dockerfile 已内置） |
| 9 | `--frozen-lockfile` 失败 | PC 上 `pnpm install --lockfile-only` 更新 lockfile 后重新部署 |

## 6. 回退方案

- 容器配置：`/volume2/dev/shell/backup_kugou_api_container_*.json`（`docker inspect` 备份）。
- 镜像版本：`docker tag kugou-api:latest kugou-api:vX` 固定旧版（tag 后不算 dangling，prune 不清）。
- 凭证：`musicAPI/` 有 Drive 双向同步备份（NAS ↔ PC）。
