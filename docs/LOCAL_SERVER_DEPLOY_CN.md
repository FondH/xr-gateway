# 定制版 Sub2API：本机更新、服务器部署

本机仓库路径：`G:\openclaw!\smalltools\zhongzhuan\enterprise-ai-gateway\sub2api-src`。本机的 `origin` 是官方 `Wei-Shaw/sub2api`，`personal` 是自己的 `FondH/xr-gateway`。定制分支为 `user-ranking-custom`；个人仓库和服务器使用 `main`。服务器目录为 `/home/fond/xr-gateway`。

当前服务器使用 Docker Compose：应用镜像从本仓库的 `Dockerfile` 构建，PostgreSQL 和 Redis 使用官方 Compose 的容器及本地数据目录。任何版本更新均先在本机合并和测试，再推送个人仓库，最后在服务器拉取、构建和手动切换。不要在服务器合并官方分支，也不要运行只下载官方镜像的更新脚本。

## 本机：合并官方更新并推送

在 PowerShell 中进入仓库：

```powershell
cd 'G:\openclaw!\smalltools\zhongzhuan\enterprise-ai-gateway\sub2api-src'
git switch user-ranking-custom
git status --short
git fetch origin
git merge origin/main
```

先处理 `git status` 报告的已跟踪修改，避免它们阻止合并。`backend/run_sub2api.bat`、`backend/config.yaml`、`backend/data/`、`deploy/.env` 和数据库数据不得提交到公开仓库。合并冲突时编辑冲突文件，`git add <文件>` 后执行 `git commit`；如果无需合并，Git 会报告已是最新。

本机验证（Go 未加入 PATH，使用现有安装位置）：

```powershell
cd backend
& 'G:\Programer\go\bin\go.exe' test ./internal/repository ./internal/handler/admin
cd ../frontend
pnpm install --frozen-lockfile
pnpm typecheck
pnpm build
cd ..
git diff --check
git status --short
```

修复测试问题并提交定制改动后，再推送服务器使用的分支：

```powershell
git push personal HEAD:main
git ls-remote personal refs/heads/main
```

检查远端哈希与 `git rev-parse HEAD` 一致。个人仓库的 `main` 必须只向前推进；不要对已推送的定制提交执行 rebase 或强制推送。若本机 GitHub 代理 `127.0.0.1:7890` 不可用，可只对该次命令覆盖代理：`git -c http.proxy= push personal HEAD:main`。

## 服务器：拉取、备份、构建、切换

SSH 登录 `fond@192.168.31.186` 后：

```bash
cd /home/fond/xr-gateway
git status --short --branch
git pull --ff-only
git log -1 --oneline
sudo docker compose -f deploy/docker-compose.local.yml -f deploy/docker-compose.custom.yml config --quiet
```

先备份正在运行的数据库和服务器配置，给旧镜像加一个保留标签，再构建应用镜像。以下数据库备份命令适用于 PostgreSQL 容器已经启动的情况；首次部署数据库尚未启动时跳过该步骤。

```bash
umask 077
mkdir -p /home/fond/backups
sudo docker compose -f deploy/docker-compose.local.yml -f deploy/docker-compose.custom.yml \
  exec -T postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' \
  > "/home/fond/backups/sub2api-$(date +%Y%m%d-%H%M%S).sql"
chmod 600 /home/fond/backups/sub2api-*.sql
tar -czf "/home/fond/backups/sub2api-config-$(date +%Y%m%d-%H%M%S).tgz" -C deploy .env data
sudo docker image tag xr-gateway:local "xr-gateway:pre-update-$(date +%Y%m%d-%H%M%S)"
sudo docker image ls xr-gateway
sudo docker compose -f deploy/docker-compose.local.yml -f deploy/docker-compose.custom.yml build sub2api
sudo docker run --rm --entrypoint /app/sub2api xr-gateway:local -version
```

执行备份后确认 SQL 文件非空。`deploy/.env`、`deploy/data/`、`deploy/postgres_data/` 和 `deploy/redis_data/` 是服务器私有数据，升级时保留。应用启动会执行数据库迁移，回退镜像前应先检查迁移是否需要恢复数据库备份。

由你决定切换时间，再手动启动或更新容器：

```bash
sudo docker compose -f deploy/docker-compose.local.yml -f deploy/docker-compose.custom.yml up -d --no-build
sudo docker compose -f deploy/docker-compose.local.yml -f deploy/docker-compose.custom.yml ps
sudo docker compose -f deploy/docker-compose.local.yml -f deploy/docker-compose.custom.yml logs --tail=100 sub2api
```

若只是查看日志或停止应用，不需要删除数据卷：

```bash
sudo docker compose -f deploy/docker-compose.local.yml -f deploy/docker-compose.custom.yml logs -f sub2api
sudo docker compose -f deploy/docker-compose.local.yml -f deploy/docker-compose.custom.yml stop sub2api
```

## lanproxy 客户端

服务器上的 Linux amd64 客户端安装于 `/home/fond/lanproxy/client_linux_amd64`，由 [ffay/lanproxy-go-client](https://github.com/ffay/lanproxy-go-client) 的 `682c267` 源码编译。该项目的 GitHub Release 没有直接附带客户端文件；以后需要重新构建时，先从对应提交下载源码，再用 Go 交叉编译 `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o client_linux_amd64 ./src/main`。旧源码依赖 `github.com/urfave/cli`，这次构建使用 `v1.22.17`。它与 [ffay/lanproxy](https://github.com/ffay/lanproxy) 的服务端配套使用。客户端无需在 Sub2API 容器内运行：lanproxy 管理后台的代理目标填 `127.0.0.1:8080`，也就是服务器宿主机上的 Sub2API 映射端口。PostgreSQL 和 Redis 不应建立公网穿透规则。

先在 lanproxy 服务端后台创建客户端和 TCP 代理规则，取得服务端地址、客户端连接端口和客户端密钥。普通连接端口通常为 `4900`，SSL 连接端口通常为 `4993`，但以你自己的服务端配置为准。然后在服务器上手动试连：

```bash
/home/fond/lanproxy/client_linux_amd64 -s <lanproxy服务端地址> -p <连接端口> -k <客户端密钥>
```

该旧版客户端会将客户端密钥写入日志，且 `-k` 参数会出现在进程命令行。请勿在共享终端或公开日志中使用真实密钥；之后配置长期运行方式时需考虑这一点。它的 SSL 模式在未提供证书时会跳过证书验证，源码对自定义证书的处理也需要另行验证；配置加密连接前应先解决这两个问题。尚未设置服务端地址和密钥前，客户端不应启动。公网入口还需要在服务端配置域名/端口及 HTTPS 终止；仅下载客户端不会自动开放公网访问。当前 Sub2API 映射是 `0.0.0.0:8080`。建议在公网穿透启用前，将服务器 `deploy/.env` 中的 `BIND_HOST` 改成 `127.0.0.1`，限制宿主机端口仅本机可访问，然后用上述 Compose 命令重新创建应用容器。
