# Context

KuGouMusicApi 是酷狗音乐的非官方 NodeJS API 服务（fork 自 MakcRe/KuGouMusicApi）：通过伪造请求头调用官方 Web API。支持两种运行模式，项目指南见 `CLAUDE.md`。

## Language

**服务模式**:
作为 Express HTTP 服务运行（`app.js` 启动），客户端经 HTTP 调用接口。
_Avoid_: 服务器部署

**库模式（编程式调用）**:
作为库 `require` 进宿主项目直接调用模块函数，不起 HTTP 服务。
_Avoid_: SDK 模式

**伪造请求头**:
本项目与官方通信的根本手段（README「工作原理」原词）：伪造 Referer/Cookie/签名等头调用官方 API，配合 CSRF 参数。
_Avoid_: 爬虫、逆向（此语境不用）

**KRC**:
酷狗加密歌词格式，经 pako（zlib）解压后解码。相关加密工具：crypto-js（AES/MD5）、node-forge（RSA）。
_Avoid_: LRC（KRC 是上游原始格式，LRC 是转换产物语境）
