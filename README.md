# caddy-build

通过 GitHub Actions 自动构建并发布到 GHCR 的自定义 Caddy 镜像。

当前镜像基于官方 `caddy:builder` 使用 `xcaddy` 编译 Caddy，并在最终镜像中替换官方 `caddy:latest` 的 `/usr/bin/caddy`。

同时会把镜像中的 Caddy 二进制发布到 GitHub Release，方便不使用 Docker 的场景。

## 镜像地址

```text
ghcr.io/jiajiaxd/caddy-build
```

拉取最新镜像：

```bash
docker pull ghcr.io/jiajiaxd/caddy-build:latest
```

## 二进制下载

在 [Releases](https://github.com/jiajiaxd/caddy-build/releases) 页面下载对应架构的压缩包，二进制与同次发布的 Docker 镜像完全一致：

- `caddy_<版本>_linux_amd64.tar.gz`
- `caddy_<版本>_linux_arm64.tar.gz`
- `checksums.txt`：SHA-256 校验和

Release 标签格式为 `<Caddy 版本>-<构建日期>`，例如 `v2.11.7-20261006`。

```bash
gh release download --repo jiajiaxd/caddy-build \
  --pattern 'caddy_*_linux_amd64.tar.gz' --pattern checksums.txt
sha256sum -c --ignore-missing checksums.txt
tar -xzf caddy_*_linux_amd64.tar.gz
sudo install -m 755 caddy /usr/local/bin/caddy
```

## 已包含插件

- `github.com/caddy-dns/alidns`
- `github.com/caddy-dns/cloudflare`
- `github.com/caddy-dns/tencentcloud`

这些插件可用于 Caddy 的 DNS-01 ACME 验证，适合需要通过 Cloudflare 或腾讯云 DNS 自动申请证书的场景。

## 自动构建

仓库使用 `.github/workflows/build-caddy.yml` 自动构建并推送镜像到 GitHub Container Registry。

触发条件：

- 每天北京时间 04:00 定时检查
- 手动触发 `workflow_dispatch`

发布平台：

- `linux/amd64`
- `linux/arm64`

镜像标签：

- `latest`：最新构建
- `main`：`main` 分支构建
- `sha-*`：按提交 SHA 生成的镜像标签

每次运行会先查询 Caddy 和插件的最新版本，并与 GHCR 上 `latest` 镜像中 Caddy 二进制的 Go module 信息比较；如果没有变化则跳过发布。有变化时会构建并推送镜像，再用 `scripts/package-release.sh` 从刚推送的镜像中取出各架构的二进制，打包后发布到 GitHub Release。

## 本地调试构建

```bash
docker build -t caddy-custom:latest .
```

## 验证插件

拉取镜像后可以查看 Caddy 版本和已加载模块：

```bash
docker run --rm ghcr.io/jiajiaxd/caddy-build:latest caddy version
docker run --rm ghcr.io/jiajiaxd/caddy-build:latest caddy list-modules | grep dns.providers
```

如果是在本地调试构建，把镜像名替换为 `caddy-custom:latest` 即可。

预期输出中应包含：

```text
dns.providers.cloudflare
dns.providers.alidns
dns.providers.tencentcloud
```

## 运行示例

挂载本地 `Caddyfile` 和数据目录：

```bash
docker run -d \
  --name caddy \
  -p 80:80 \
  -p 443:443 \
  -v "$PWD/Caddyfile:/etc/caddy/Caddyfile:ro" \
  -v caddy_data:/data \
  -v caddy_config:/config \
  ghcr.io/jiajiaxd/caddy-build:latest
```

Cloudflare DNS-01 示例：

```caddyfile
example.com {
	tls {
		dns cloudflare {env.CLOUDFLARE_API_TOKEN}
	}

	respond "Hello from Caddy"
}
```

阿里云 DNS-01 示例：

```caddyfile
example.com {
	tls {
		dns alidns {
			access_key_id {env.ALICLOUD_ACCESS_KEY_ID}
			access_key_secret {env.ALICLOUD_ACCESS_KEY_SECRET}
		}
	}

	respond "Hello from Caddy"
}
```

腾讯云 DNS-01 示例：

```caddyfile
example.com {
	tls {
		dns tencentcloud {
			secret_id {env.TENCENTCLOUD_SECRET_ID}
			secret_key {env.TENCENTCLOUD_SECRET_KEY}
		}
	}

	respond "Hello from Caddy"
}
```

运行时通过环境变量传入密钥：

```bash
docker run -d \
  --name caddy \
  -p 80:80 \
  -p 443:443 \
  -e CLOUDFLARE_API_TOKEN="your-token" \
  -v "$PWD/Caddyfile:/etc/caddy/Caddyfile:ro" \
  -v caddy_data:/data \
  -v caddy_config:/config \
  ghcr.io/jiajiaxd/caddy-build:latest
```

## 添加插件

在 `Dockerfile` 的 `xcaddy build` 命令中继续追加 `--with` 参数即可：

```dockerfile
RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare \
    --with github.com/caddy-dns/tencentcloud
```

修改后推送到 `main` 分支，再手动触发 workflow（或等待每日定时任务）即可构建并发布到 GHCR 和 GitHub Release。需要先本地验证时，可以使用 `docker build -t caddy-custom:latest .`。
