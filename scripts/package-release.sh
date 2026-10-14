#!/usr/bin/env bash
# 从已发布的多架构镜像中取出 caddy 二进制并打包，供 GitHub Release 使用。
#
# 用法: scripts/package-release.sh <镜像引用> <输出目录> [构建日期 YYYYMMDD]
#
# 输出目录中会生成:
#   caddy_<版本>_linux_<架构>.tar.gz
#   checksums.txt
#   tag.txt    Release 标签，例如 v2.11.7-20261006
#   notes.md   Release 说明

set -euo pipefail

IMAGE="${1:?缺少镜像引用}"
OUT_DIR="${2:?缺少输出目录}"
BUILD_DATE="${3:-$(date -u +%Y%m%d)}"
PLATFORMS=(linux/amd64 linux/arm64)

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

REPO="${IMAGE%@*}"
REPO="${REPO%:*}"
docker buildx imagetools inspect --raw "$IMAGE" > "$WORK_DIR/index.json"

for platform in "${PLATFORMS[@]}"; do
  arch="${platform#*/}"
  mkdir -p "$WORK_DIR/$arch"
  # 按单架构 manifest 的 digest 拉取，避免 containerd 镜像存储下多架构 digest 冲突
  digest="$(jq -r --arg os "${platform%/*}" --arg arch "$arch" \
    '.manifests[] | select(.platform.os == $os and .platform.architecture == $arch) | .digest' \
    "$WORK_DIR/index.json")"
  if [[ -z "$digest" ]]; then
    echo "镜像中没有 $platform" >&2
    exit 1
  fi
  docker pull -q "$REPO@$digest" > /dev/null
  container="$(docker create --platform "$platform" "$REPO@$digest")"
  docker cp "$container:/usr/bin/caddy" "$WORK_DIR/$arch/caddy" > /dev/null
  docker rm "$container" > /dev/null
done

# 二进制是 Go 程序，用 builder 镜像读取模块信息，无需执行目标架构的程序
docker run --rm -v "$WORK_DIR/amd64:/work" caddy:builder \
  go version -m /work/caddy > "$WORK_DIR/modules.txt"

CADDY_VERSION="$(awk '$1 == "dep" && $2 == "github.com/caddyserver/caddy/v2" { print $3 }' "$WORK_DIR/modules.txt")"
if [[ -z "$CADDY_VERSION" ]]; then
  echo "无法从二进制中读取 Caddy 版本" >&2
  exit 1
fi

TAG="${CADDY_VERSION}-${BUILD_DATE}"

for platform in "${PLATFORMS[@]}"; do
  arch="${platform#*/}"
  tar -C "$WORK_DIR/$arch" -czf "$OUT_DIR/caddy_${CADDY_VERSION}_linux_${arch}.tar.gz" caddy
done

(cd "$OUT_DIR" && sha256sum caddy_*.tar.gz > checksums.txt)

echo "$TAG" > "$OUT_DIR/tag.txt"

{
  echo "Caddy \`${CADDY_VERSION}\`，构建日期 ${BUILD_DATE}。"
  echo
  echo "Docker 镜像: \`$IMAGE\`"
  echo
  echo "## 模块版本"
  echo
  echo '```text'
  awk '$1 == "dep" && ($2 == "github.com/caddyserver/caddy/v2" || $2 ~ /^github\.com\/caddy-dns\//) { print $2, $3 }' "$WORK_DIR/modules.txt"
  echo '```'
  echo
  echo "## 校验和"
  echo
  echo '```text'
  cat "$OUT_DIR/checksums.txt"
  echo '```'
} > "$OUT_DIR/notes.md"

echo "已生成 $TAG:"
ls -l "$OUT_DIR"
