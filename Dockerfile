FROM node:lts-alpine

# apk 换国内镜像（阿里云）加速 tini 安装
RUN sed -i 's|dl-cdn.alpinelinux.org|mirrors.aliyun.com|g' /etc/apk/repositories \
    && apk add --no-cache tini

RUN corepack enable

# 全局写 npm 镜像（对 root 与 node 用户均生效）；锁定 pnpm 版本（与 PC 侧一致）
# --force 覆盖 corepack enable 创建的 pnpm shim
RUN npm config --location=global set registry https://registry.npmmirror.com && npm install -g pnpm@11.21.0 --force

ENV NODE_ENV=production

WORKDIR /app

RUN chown node:node /app

COPY --chown=node:node package.json pnpm-lock.yaml ./

USER node

# 设置 pnpm 使用国内镜像源并安装依赖
RUN pnpm config set registry https://registry.npmmirror.com && \
    pnpm install --prod --frozen-lockfile

COPY --chown=node:node . ./

EXPOSE 3001

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "app.js"]
