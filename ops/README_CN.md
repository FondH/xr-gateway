# Sub2API 运维界面

双击 `ops/Sub2API-Operations.bat`。界面可查看本机开发实例（18271）、本机生产实例（18272）、Linux Docker（8080）和最近数据库同步时间。保存连接设置后，密码用 Windows DPAPI 加密保存在 `C:\ProgramData\Sub2API\operations.json`；密码框留空会保留原值。界面会请求管理员权限以注册定时任务。

首次配置：

1. 在 Linux 的 `/home/fond/xr-gateway/deploy/.env` 设置非空 `REDIS_PASSWORD`，并确认 `POSTGRES_PASSWORD`。Redis 密码可用 `openssl rand -hex 32` 生成。不要把该文件提交到 Git。
2. 在界面“连接设置”填写 Linux 地址、数据库用户/库名、PostgreSQL 与 Redis 密码，保存。两端应用必须使用相同的 JWT 和加密密钥。
3. 点“部署并启动 Linux”时，界面会推送本机**已提交**的代码，Linux 拉取、备份数据库、构建镜像，然后通过 `docker-compose.lan.yml` 重新创建并启动容器。PostgreSQL/Redis 只绑定 Linux 指定的局域网 IP（默认 `192.168.31.186`）；如服务器 IP 不同，先在服务器 `.env` 设置 `LAN_BIND_HOST`。本机现有 18271 服务不会被操作。
4. Linux 启动并能从 Windows 连接数据库后，可点“立即同步数据库”验证。同步只更新本机独立的 `sub2api_prod_snapshot` 库，不覆盖开发库 `sub2api`。确认正常后点“启用 00:00 同步”。电脑在凌晨关机时任务会在下次可用时补跑。

“获取官方更新”仅执行 `git fetch origin`，合并、测试和提交仍由你手动完成。“启动全部”会先部署并启动 Linux、确认健康，然后启动本机生产实例。本机生产仅监听 `127.0.0.1:18272`，连接 Linux 的 PostgreSQL/Redis；开发模式继续使用本机数据库。GUI 不会停止任何本机 Sub2API 进程。

两台应用同时运行不等于公网请求已自动分流；公网负载均衡或 lanproxy 的双后端规则仍需单独配置。
