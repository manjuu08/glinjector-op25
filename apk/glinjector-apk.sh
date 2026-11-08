#!/bin/sh
# 在 OpenWrt 25 (apk) 路由器上，把 glinjector 的 ipk 转成 apk 并安装
# 用法:  sh glinjector-apk.sh [ipk路径]      默认找 /tmp/glinjector_*.ipk
# 卸载:  apk del glinjector   (若走了兜底安装则运行 /usr/sbin/glinjector-uninstall)

set -e
PKG=glinjector
IPK="${1:-$(ls /tmp/${PKG}_*.ipk 2>/dev/null | head -n 1)}"
[ -f "$IPK" ] || { echo "找不到 ipk 文件，请先上传到 /tmp/ 或在参数中指定路径"; exit 1; }

if [ -f /etc/glversion ] && grep -qE "^[1-4]\.[0-6]\." /etc/glversion; then
	echo '您的固件版本低于4.7.0，请尝试较低版本的插件'
	exit 1
fi

W=/tmp/$PKG-apk-build
rm -rf "$W"; mkdir -p "$W/ipk" "$W/ctl" "$W/root" "$W/scripts"
cd "$W/ipk"
# OpenWrt 编出的 ipk 是 tar.gz，老版本是 ar，两种都兼容
tar -xzf "$IPK" 2>/dev/null || ar x "$IPK"
tar -xzf control.tar.gz -C "$W/ctl"
tar -xzf data.tar.gz -C "$W/root"

# 3.0.7-8 -> 3.0.7-r8 (apk 版本号格式)
V=$(sed -n 's/^Version: *//p' "$W/ctl/control")
VER="${V%-*}-r${V##*-}"
OUT=/tmp/${PKG}-${VER}.apk

cat > "$W/scripts/post-install" <<'EOF'
#!/bin/sh
[ -f /etc/nginx/conf.d/gl.conf ] && sed -i '/cgi-bin/,/}/{/X-Frame-Options/d}' /etc/nginx/conf.d/gl.conf
nginx -s reload 2>/dev/null
echo '安装后请进入"系统 > 个性化"点击应用按钮'
exit 0
EOF
cp "$W/scripts/post-install" "$W/scripts/post-upgrade"

cat > "$W/scripts/pre-deinstall" <<'EOF'
#!/bin/sh
rm -f /www/js/glinjector-*
cp -f /rom/www/gl_home.html /www/ 2>/dev/null
cp -f /rom/etc/nginx/conf.d/gl.conf /etc/nginx/conf.d/ 2>/dev/null
nginx -s reload 2>/dev/null
exit 0
EOF
chmod 755 "$W/scripts/"*

if apk mkpkg --help >/dev/null 2>&1; then
	apk mkpkg \
		--info "name:$PKG" \
		--info "version:$VER" \
		--info "arch:noarch" \
		--info "description:GlInet UI Injector" \
		--info "license:GPL-3.0" \
		--info "origin:$PKG" \
		--info "maintainer:VMatrices <vmatrices@outlook.com>" \
		--script "post-install:$W/scripts/post-install" \
		--script "post-upgrade:$W/scripts/post-upgrade" \
		--script "pre-deinstall:$W/scripts/pre-deinstall" \
		--files "$W/root" \
		--output "$OUT"
	echo "已生成 $OUT"
	apk add --allow-untrusted "$OUT"
	echo "安装完成。卸载: apk del $PKG"
else
	# 兜底：apk 不带 mkpkg 时直接拷文件，并生成卸载脚本
	echo "当前 apk 不支持 mkpkg，改为直接安装文件"
	(cd "$W/root" && find . -type f | sed 's#^\.##') > "$W/files.list"
	cp -a "$W/root/." /
	mkdir -p /etc/$PKG
	cp "$W/files.list" /etc/$PKG/files.list
	{
		echo '#!/bin/sh'
		sed -n '2,$p' "$W/scripts/pre-deinstall" | grep -v '^exit'
		echo 'grep -v -e "^/etc/config/" -e "^/www/upload/" /etc/glinjector/files.list | xargs rm -f'
		echo 'rm -rf /etc/glinjector /usr/sbin/glinjector-uninstall'
		echo 'echo "glinjector 已卸载"'
	} > /usr/sbin/glinjector-uninstall
	chmod 755 /usr/sbin/glinjector-uninstall
	sh "$W/scripts/post-install"
	echo "安装完成。卸载: glinjector-uninstall"
fi

rm -rf "$W"
