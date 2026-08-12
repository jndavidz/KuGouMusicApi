# 群晖 NAS 上用源码构建 kugou-api 镜像 — 环境与需求指南

> 适用范围：NAS（群晖 DSM 7.2+ / Container Manager）上用本地源码构建并运行 kugou-api 容器。
> 文中实测值取自本机 NAS（2026-08-12 验证；含 pnpm 两侧升级、Dockerfile 源优化、compose build 段修复后的状态）。

---

## 1. 架构概览（三项分离）

| 角色 | 位置 | 说明 |
|---|---|---|
| 代码唯一源头 | PC `D:\repos\kugou_api`（git，zxs 分支） | 开发、merge 上游、版本管理都在这里 |
| NAS 部署副本 | `/volume2/docker/kugou_api` | 仅作为 docker build 输入（构建上下文），**非 Drive 同步区**，不含凭证 |
| 凭证权威位置 | `/volume2/dev/data/api-secrets/kugou_api.env` | Drive 双向同步 ↔ PC `D:\dev\data\api-secrets\`，容器以 `:ro` 挂载 |
| 定时脚本 | `scripts/kugou_refresh.sh` `scripts/kugou_vip.sh` | 仓库内版本管理；NAS 上部署于 `/volume2/dev/shell/bin/`，DSM 任务计划调用 |

> ⚠️ **不要**把代码放进 `/volume2/dev`（Drive 同步根），否则会被双向镜像回 PC `D:\dev`，污染非代码区。
> ⚠️ NAS 部署目录由 `deploy.sh` 每次 **清空重建**（`rm -rf`），保证与 PC 仓库精确镜像、无残留模块。

---

## 2. 宿主机环境需求（NAS 侧）

| 项 | 实测值 | 要求 |
|---|---|---|
| 系统 | DSM 7.3.2-86009 | DSM 7.2+（Container Manager 要求） |
| Docker 套件 | Container Manager（新版） | 已安装且运行 |
| docker CLI | 24.0.2（`/usr/local/bin/docker`） | 默认不在 PATH，用全路径 |
| docker compose | v2.20.1 | 插件形式 `docker compose` |
| 操作权限 | `zxsadmin` 在 `docker` 组 | 免 sudo 操作 docker |
| 磁盘 | `/volume2` 空闲 191G | 实际需求 <2GB |

**磁盘估算**：kugou-api 镜像 ~297MB + node:lts-alpine 基础层 + pnpm 依赖层 + BuildKit 缓存 ≈ **<2GB**。

---

## 3. 源码内容（构建上下文）

部署目录 `/volume2/docker/kugou_api` 必须包含（由 `deploy.sh` 维护）：

- `Dockerfile`、`package.json`、`pnpm-lock.yaml`（**严格锁定依赖版本**）
- 运行时：`app.js`、`server.js`、`main.js`、`index.js`、`module/`（168 个 API 模块）、`util/`、`public/`
- `docker-compose.yml`（含 **`build:` 段**，见第 6 节）
- `.dockerignore`（控制 COPY 范围，阻止 `.git`/`.env`/`cookies.txt` 打进镜像）

**传输时排除**（deploy.sh 已内置）：`.git`、`.zcode`、`node_modules`、`cookies.txt`、`.env`、`.env.example`（敏感凭证不进 NAS 部署目录）。

---

## 4. 网络需求（构建过程）

| 目标 | 用途 | 状态 | 备注 |
|---|---|---|---|
| `registry.npmmirror.com` | pnpm 依赖安装 | ✅ | Dockerfile 内 `pnpm config set registry`（node 用户） |
| `registry.npmmirror.com` | npm 全局 registry | ✅ | Dockerfile 内 `npm config --location=global set registry`（**全用户生效**） |
| `mirrors.aliyun.com` | apk 安装 tini | ✅ | 已换阿里云源（原官方源国内慢） |
| github.com | 构建不需要 | ❌ 仅 25KB/s | 仅源码同步可能用到，走内网替代 |

> 构建全程只走国内镜像源（npmmirror + 阿里云），不碰 github.com。

---

## 5. 镜像内构建环境（由 Dockerfile 决定）

| 项 | 实测值 |
|---|---|
| 基础镜像 | `node:lts-alpine`（当前 lts = node **v24.15.0**，160MB，amd64） |
| 包管理器 | pnpm **11.21.0**（`npm install -g pnpm@11.21.0 --force` **锁定**，PC 侧同版本） |
| 依赖安装 | `pnpm install --prod --frozen-lockfile`（生产依赖，严格按 lockfile） |
| 进程管理 | tini（`ENTRYPOINT ["/sbin/tini","--"]`） |
| 启动 | `node app.js` → 监听 3001 |
| 端口/网络 | `PORT=3001`，compose `network_mode: "host"` |

**依赖锁定要求**：merge 上游后若 `package.json` 依赖变化，必须先更新 `pnpm-lock.yaml`：
```bash
# PC 侧（pnpm 11.21.0 与 NAS 一致，便携目录 D:\PortableApps\_sys\node\npm_global）
pnpm install --lockfile-only
```
`deploy.sh` 会自动做一次 `--frozen-lockfile --lockfile-only` 校验拦截不一致。

---

## 6. 构建与更新流程（deploy.sh 一键）

```bash
# PC 端（Git Bash），一条命令完成全部：
cd /d/repos/kugou_api && ./deploy.sh
```

deploy.sh 内部三步：
1. **lockfile 校验**（PC 有 pnpm 时）：`pnpm install --frozen-lockfile --lockfile-only`，不一致即中止；
2. **传输 + 构建**：`tar`（排除敏感/无关项）→ ssh 到 NAS → `chmod 644` 凭证文件（**幂等修复 ACL**，防 Drive 重置）→ `rm -rf` 清空部署目录 → 解压 → `docker compose up -d --build`；
3. **验证**：`curl http://10.10.10.2:3001/` 期望 200 + `/login/token` 探活（确认凭证/设备身份链路生效，防止"假正常"）。

**⚠️ 关键前提：`docker-compose.yml` 必须含 `build:` 段**，否则 `--build` 被忽略、代码改动永远不进镜像：

```yaml
services:
  kugou-api:
    image: kugou-api:latest
    build:               # ← 缺了它，"重建"只是用旧镜像重启
      context: .
      dockerfile: Dockerfile
```

**正常更新耗时**：依赖不变时层缓存命中 → 秒级；依赖变更 → 1-3 分钟（pnpm install 走 npmmirror）。

---

## 7. 已知坑与故障排查

1. **compose 缺 `build:` 段**（最隐蔽）：`--build` 不报错、容器照常 Running，但镜像从不重建。已修复；改动 compose 后务必验证镜像 `Created` 时间刷新（`docker image inspect kugou-api:latest`）。
2. **`corepack enable` 与 `npm install -g pnpm` 冲突（EEXIST）**：corepack 先占用了 `/usr/local/bin/pnpm`，npm 全局安装必须加 `--force` 覆盖。
3. **凭证 ACL 权限坑**：挂载的 `kugou_api.env` 若被 Drive 同步重置 ACL，容器内 `/app/.env` 变 `000`，node 用户（uid 1000）读不到 → 服务照常启动但**设备身份加载失败（登录态失效）**。修复：`chmod 644 /volume2/dev/data/api-secrets/kugou_api.env && docker restart kugou-api`。**deploy.sh 每次部署已内置幂等 chmod 防御**。
4. **`--frozen-lockfile` 失败**：lockfile 与 package.json 不一致 → PC 上 `pnpm install --lockfile-only` 更新后重新部署。
5. **构建缓存被清**：NAS 上有计划任务 `Docker_Auto_Prune`，已改为
   `docker image prune -f && docker builder prune -f --filter until=168h`（保留 7 天构建缓存；只清 dangling 镜像，不动停止的容器）。
6. **部署目录放非同步区**：必须 `/volume2/docker/...`，不要放 `/volume2/dev`（会同步回 PC `D:\dev`）。
7. **构建超时/网络失败**：检查 npmmirror/阿里云可达性；确属缓存污染可 `docker compose build --no-cache`（明显更慢，慎用）。

---

## 8. 回退方案

- 容器配置备份：`/volume2/dev/shell/backup_kugou_api_container_*.json`（`docker inspect` 输出）。
- 镜像：`kugou-api:latest` 每次构建覆盖旧 tag；如需回退，构建时 `docker tag kugou-api:latest kugou-api:v1.6.0` 固定旧版本（tag 住后不算 dangling，`prune` 不会清）。
- 凭证：`/volume2/dev/data/api-secrets/` 有 Drive 双向备份，PC `D:\dev\data\api-secrets\` 同份。
