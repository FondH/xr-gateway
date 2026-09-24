# Sub2API 运维速查

## 访问与开关

服务器目录：`/home/fond/xr-gateway`。当前应用、PostgreSQL、Redis 均在运行；局域网访问 `http://192.168.31.186:8080`。宿主机端口 `8080` 映射到 Sub2API 容器端口 `8080`；同一 Compose 网络里的其他容器可用 `http://sub2api:8080`。lanproxy 客户端运行在宿主机，穿透目标用 `127.0.0.1:8080`。

SSH 登录服务器后，在当前终端定义一次 `dc`：

```bash
cd /home/fond/xr-gateway
dc() { sudo docker compose -f deploy/docker-compose.local.yml -f deploy/docker-compose.custom.yml -f deploy/docker-compose.lan.yml "$@"; }
```

以下命令按需要单独执行：

| 目的 | 命令 |
| --- | --- |
| 查看状态 | `dc ps` |
| 启动全部服务 | `dc up -d --no-build` |
| 关闭全部服务，保留数据 | `dc stop` |
| 只重启应用 | `dc restart sub2api` |
| 查看应用日志 | `dc logs -f sub2api`，`Ctrl+C` 只退出查看 |

Docker 服务已开机自启，三个容器配置了 `restart: unless-stopped`：运行中的容器会随服务器重启恢复；手动 `dc stop` 后不会自行恢复。需要再次运行时执行 `dc up -d --no-build`。使用局域网端口覆盖文件前，必须在未提交的 `deploy/.env` 设置非空 `REDIS_PASSWORD`。数据在 `deploy/data/`、`deploy/postgres_data/`、`deploy/redis_data/`。

## 本机更新代码

在 Windows PowerShell 中逐条执行，任何一步失败就停止。`origin` 是官方仓库，`personal` 是自己的公开仓库；不要提交 `backend/run_sub2api.bat`、配置或数据。

```powershell
cd 'G:\openclaw!\smalltools\zhongzhuan\enterprise-ai-gateway\sub2api-src'
git switch user-ranking-custom
git status --short
git fetch origin
git merge origin/main
cd backend
& 'G:\Programer\go\bin\go.exe' test ./internal/repository ./internal/handler/admin
cd ../frontend
pnpm install --frozen-lockfile
pnpm typecheck
pnpm build
cd ..
git diff --check
git push personal HEAD:main
```

合并冲突先解决并提交，测试通过再推送。已公开的定制分支使用 `merge`，不要 rebase 后强推。

## 服务器更新代码

在服务器上逐条执行，任何一步失败就停止。先备份数据库，再拉取已在本机测试并推送的代码。构建镜像不会切换正在运行的容器；最后一行由你决定何时执行。

```bash
cd /home/fond/xr-gateway
dc() { sudo docker compose -f deploy/docker-compose.local.yml -f deploy/docker-compose.custom.yml -f deploy/docker-compose.lan.yml "$@"; }
mkdir -p /home/fond/backups
umask 077
dc exec -T postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' > "/home/fond/backups/sub2api-$(date +%Y%m%d-%H%M%S).sql"
git pull --ff-only
sudo docker image tag xr-gateway:local "xr-gateway:pre-update-$(date +%Y%m%d-%H%M%S)"
dc build sub2api
sudo docker run --rm --entrypoint /app/sub2api xr-gateway:local -version
dc up -d --no-build
```

首次部署、数据库容器尚未运行时跳过备份命令。升级不会删除 `deploy/.env` 和数据目录；应用启动时可能执行数据库迁移。

## lanproxy

Go 客户端没有原生配置文件。本仓库安装的包装命令读取 `/home/fond/lanproxy/client.env`，编辑后检查并启动：

```bash
vim /home/fond/lanproxy/client.env
lanproxyctl check
lanproxyctl start
lanproxyctl status
lanproxyctl enable             # 确认正常后设置开机自启
lanproxyctl stop
```

`LANPROXY_SERVER`、`LANPROXY_PORT`、`LANPROXY_KEY` 填 lanproxy 服务端提供的值。`15732` 是 SOCKS5 下载代理，不是 lanproxy 穿透端口。旧客户端会把密钥写入服务日志和进程参数，不要公开其日志。当前 Sub2API 对所有宿主机网卡开放 `8080`；若只经 lanproxy 访问，把 `deploy/.env` 的 `BIND_HOST` 改为 `127.0.0.1`，再执行 `dc up -d --no-build`。
