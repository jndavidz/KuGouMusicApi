FROM node:lts-alpine

RUN apk add --no-cache tini

RUN corepack enable

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
