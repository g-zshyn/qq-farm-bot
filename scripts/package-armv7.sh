#!/usr/bin/env bash
# 把仓库打包成可直接部署的生产目录（含编译产物、生产依赖、systemd 单元）
# 用法: bash scripts/package-armv7.sh
# 输出: dist-pkg/qq-farm-bot-armv7-<version>.tar.gz
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

VERSION=$(node -p "require('./core/package.json').version")
OUT="${OUT:-$ROOT/dist-pkg}"
PKG="$OUT/qq-farm-bot"
TARBALL="$OUT/qq-farm-bot-armv7-${VERSION}.tar.gz"

[ -f core/client.js ] || { echo "缺少 core/client.js，请先执行 pnpm build" >&2; exit 1; }
[ -d web/dist ]       || { echo "缺少 web/dist，请先执行 pnpm build" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$PKG/core/src/utils" "$PKG/web"

cp -a core/client.js core/dist core/package.json core/package-lock.json "$PKG/core/"
cp -a core/src/gameConfig core/src/proto "$PKG/core/src/"
cp -a core/src/utils/tsdk.wasm core/src/utils/tsdk-wx.wasm "$PKG/core/src/utils/"
cp -a web/dist "$PKG/web/dist"
cp -a package.json "$PKG/package.json"
mkdir -p "$PKG/core/data"

cat > "$PKG/qq-farm-bot.service" <<'UNIT'
[Unit]
Description=QQ Farm Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/qq-farm-bot/core
Environment=NODE_ENV=production
Environment=TZ=Asia/Shanghai
Environment=ADMIN_PORT=3007
Environment=LOG_LEVEL=info
ExecStart=/usr/local/bin/node --max-old-space-size=512 client.js
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT

cat > "$PKG/install.sh" <<'INSTALL'
#!/usr/bin/env bash
set -euo pipefail
DIR=/opt/qq-farm-bot
NODE_BIN=$(command -v node || true)
[ -n "$NODE_BIN" ] || { echo "找不到 node，请先安装 Node 20"; exit 1; }
[ -d "$DIR/core" ] || { echo "请把本包解压到 $DIR"; exit 1; }
sed "s#/usr/local/bin/node#$NODE_BIN#" "$DIR/qq-farm-bot.service" > /etc/systemd/system/qq-farm-bot.service
systemctl daemon-reload
systemctl enable --now qq-farm-bot
sleep 3
systemctl --no-pager status qq-farm-bot | head -20
echo
echo "面板: http://$(hostname -I | awk '{print $1}'):3007"
echo "日志: journalctl -u qq-farm-bot -f"
INSTALL
chmod +x "$PKG/install.sh"

echo "安装生产依赖（npm ci）..."
( cd "$PKG/core" && npm ci --omit=dev --no-audit --no-fund >/dev/null )

if find "$PKG/core/node_modules" -name '*.node' | head -1 | grep -q .; then
    echo "产物中出现原生模块，无法跨架构运行" >&2
    exit 1
fi

tar -czf "$TARBALL" -C "$OUT" qq-farm-bot
echo "artifact=$TARBALL"
du -h "$TARBALL"