# caddy-build

通过 GitHub Actions 自动构建并发布到 GHCR 的自定义 Caddy 镜像。

当前镜像基于官方 `caddy:builder` 使用 `xcaddy` 编译 Caddy，并在最终镜像中替换官方 `caddy:latest` 的 `/usr/bin/caddy`。

## 镜像地址

```text
ghcr.io/jiajiaxd/caddy-build
```

拉取最新镜像：

```bash
docker pull ghcr.io/jiajiaxd/caddy-build:latest
```

## 已包含插件

- `github.com/caddy-dns/alidns`
- `github.com/caddy-dns/cloudflare`
- `github.com/caddy-dns/tencentcloud`

这些插件可用于 Caddy 的 DNS-01 ACME 验证，适合需要通过 Cloudflare 或腾讯云 DNS 自动申请证书的场景。

## 自动构建

仓库使用 `.github/workflows/build-caddy.yml` 自动构建并推送镜像到 GitHub Container Registry。

触发条件：

- 推送到 `main` 分支
- 推送 `v*` 标签
- 每天北京时间 04:00 定时检查
- 手动触发 `workflow_dispatch`
- Pull Request 会构建候选镜像用于检查，但不会推送到 GHCR

发布平台：

- `linux/amd64`
- `linux/arm64`

标签规则：

- `latest`：默认分支构建
- `main`：`main` 分支构建
- `v*`：Git 标签构建，例如 `v1.0.0`
- `sha-*`：按提交 SHA 生成的镜像标签

定时任务会先构建候选镜像，并与 GHCR 上已有的 `latest` 镜像比较 Caddy 二进制的 Go module 信息；如果 Caddy 或插件没有变化，则跳过发布。

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

修改后推送到 `main` 分支即可由 GitHub Actions 自动构建并发布到 GHCR。需要先本地验证时，可以使用 `docker build -t caddy-custom:latest .`。
