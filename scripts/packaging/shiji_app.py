#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""史记知识库 Windows 桌面启动器（PyInstaller 打包入口）。

作用：
    1. 在 127.0.0.1 上启动一个静态 HTTP 服务（站点为 exe 同目录的 docs/）
    2. 自动用默认浏览器打开首页
    3. 关闭控制台窗口即停止服务

用法：
    python scripts/packaging/shiji_app.py                # 开发模式，默认 8080
    python scripts/packaging/shiji_app.py --port 9000
    python scripts/packaging/shiji_app.py --root docs --no-browser

打包后的目录结构：
    史记知识库.exe
    _internal/
    docs/
"""

from __future__ import annotations

import argparse
import functools
import http.server
import socket
import sys
import threading
import webbrowser
from pathlib import Path

APP_TITLE = "史记知识库"
DEFAULT_PORT = 8080
PORT_SCAN = 20


class SiteHandler(http.server.SimpleHTTPRequestHandler):
    """补充常用 MIME 类型，并屏蔽逐条请求日志。"""

    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".json": "application/json; charset=utf-8",
        ".md": "text/markdown; charset=utf-8",
        ".js": "application/javascript; charset=utf-8",
        ".mjs": "application/javascript; charset=utf-8",
        ".svg": "image/svg+xml",
        ".woff2": "font/woff2",
    }

    def log_message(self, fmt, *args):  # noqa: A003 - 覆盖基类签名
        # 本地单用户场景，逐条访问日志只会刷屏；仅在出错时输出
        try:
            code = int(args[1])
        except (IndexError, TypeError, ValueError):
            return
        if code >= 400:
            super().log_message(fmt, *args)


def find_site_root(explicit: str | None) -> Path:
    """定位站点目录（必须包含 index.html）。"""
    if explicit:
        path = Path(explicit).expanduser().resolve()
        if (path / "index.html").is_file():
            return path
        raise SystemExit(f"指定的站点目录无效（缺少 index.html）：{path}")

    candidates: list[Path] = []

    if getattr(sys, "frozen", False):
        # 绿色版：exe 同目录下的 docs/
        candidates.append(Path(sys.executable).resolve().parent / "docs")
        # 单文件版：PyInstaller 解压目录下的 docs/
        meipass = getattr(sys, "_MEIPASS", None)
        if meipass:
            candidates.append(Path(meipass) / "docs")
    else:
        # 开发模式：scripts/packaging/shiji_app.py -> 仓库根/docs
        candidates.append(Path(__file__).resolve().parent.parent.parent / "docs")

    for candidate in candidates:
        if (candidate / "index.html").is_file():
            return candidate

    raise SystemExit("未找到 docs 站点目录。请把 docs 目录放在 exe 同一目录下后重试。")


def pick_port(start: int) -> int:
    """从 start 开始找一个可绑定的端口。"""
    for port in range(start, start + PORT_SCAN):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                sock.bind(("127.0.0.1", port))
            except OSError:
                continue
            return port
    raise SystemExit(f"端口 {start}-{start + PORT_SCAN - 1} 均被占用，请用 --port 指定其他端口。")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=f"{APP_TITLE} 本地启动器")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="起始端口，默认 8080")
    parser.add_argument("--root", help="站点目录（默认为 exe 同目录的 docs）")
    parser.add_argument("--no-browser", action="store_true", help="启动后不自动打开浏览器")
    args = parser.parse_args(argv)

    site_root = find_site_root(args.root)
    port = pick_port(args.port)

    handler = functools.partial(SiteHandler, directory=str(site_root))
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    httpd.daemon_threads = True

    url = f"http://127.0.0.1:{port}/"

    print("=" * 56)
    print(f"  {APP_TITLE}")
    print("=" * 56)
    print(f"  站点目录: {site_root}")
    print(f"  访问地址: {url}")
    print(f"  首页    : {url}index.html")
    print(f"  Wiki    : {url}wiki/")
    print(f"  地铁图  : {url}app/metro/")
    print("=" * 56)
    print("  关闭本窗口即可停止服务")
    print()

    if not args.no_browser:
        # 稍等片刻再打开，确保服务已进入监听循环
        threading.Timer(0.8, webbrowser.open, args=[url]).start()

    try:
        httpd.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    print("服务已停止")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
