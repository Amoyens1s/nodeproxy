# BunProxy - 基于 Bun 的高性能 HTTP/2 代理服务器

BunProxy 是一个高性能、独立的 HTTP/2 正向代理服务器，使用[Bun](https://bun.sh/)运行时构建，相比 Node.js 版本提供更高的性能和更低的内存占用。该代理服务器打包为单一二进制文件，无需安装任何依赖即可在 Linux 上运行。它支持 HTTPS 连接、基本认证和通过 Let's Encrypt 的自动证书管理。

## 性能优势

Bun 相比 Node.js 有显著的性能优势：

- **更快的启动速度**：通常比 Node.js 快 3-4 倍
- **更高的 HTTP 处理性能**：处理请求时延迟更低，吞吐量更高
- **更低的内存占用**：运行时消耗的内存更少
- **原生二进制编译**：提供更好的性能和安全性

## 功能特性

- **独立二进制**：无需安装 Node.js 或任何其它依赖
- **HTTP/2 支持**：完整的 HTTP/2 支持以提高性能
- **Systemd 集成**：通过`systemctl`轻松管理服务
- **自动 SSL 配置**：一键设置 Let's Encrypt 证书
- **灵活配置**：简单的 JSON 配置文件
- **安全性**：以非特权用户身份运行，权限限制
- **一键安装**：简单的安装脚本，无需手动配置

## 安装方法

安装非常简单。只需下载适合您系统的最新版本并运行安装脚本。

1. **下载最新版本** 从[发布页面](https://github.com/Amoyens1s/nodeproxy/releases)下载。
   选择适合您系统的压缩包（例如 `bunproxy-v1.0.0-linux.tar.gz`）。

2. **解压文件**:

   ```bash
   tar -xzf bunproxy-v1.0.0-linux.tar.gz
   cd bunproxy-v1.0.0-linux
   ```

3. **运行安装脚本**:
   ```bash
   sudo ./install.sh
   ```

安装脚本会引导您完成设置过程，包括域名配置和自动 SSL 证书生成。

## 从源代码构建（开发者）

如果您想从源代码构建代理，需要安装 Bun：

1. **克隆仓库**:

   ```bash
   git clone https://github.com/Amoyens1s/nodeproxy.git
   cd nodeproxy
   ```

2. **安装 Bun**:

   ```bash
   curl -fsSL https://bun.sh/install | bash
   ```

3. **构建二进制文件**:
   ```bash
   bun run build
   ```
   这将在`dist/`目录中创建一个二进制文件。

## 配置文件

配置文件位于`/etc/bunproxy/config.json`。安装脚本会为您创建此文件。

```json
{
  "port": 8443,
  "host": "0.0.0.0",
  "auth": {
    "enabled": true,
    "username": "admin",
    "password": "changeme"
  },
  "ssl": {
    "cert": "/etc/bunproxy/ssl/fullchain.pem",
    "key": "/etc/bunproxy/ssl/privkey.pem"
  },
  "domain": "proxy.example.com",
  "email": "admin@example.com",
  "logging": {
    "level": "info",
    "timestamp": true
  },
  "timeout": 30000
}
```

## 服务管理

代理作为`systemd`服务运行。

```bash
# 检查服务状态
sudo systemctl status bunproxy

# 启动/停止/重启服务
sudo systemctl start bunproxy
sudo systemctl stop bunproxy
sudo systemctl restart bunproxy

# 查看日志
sudo journalctl -u bunproxy -f

# 证书更新后重新加载服务
sudo systemctl reload bunproxy
```

## 卸载

要完全移除 BunProxy，请运行您首次解压文件的目录中的`uninstall.sh`脚本。

```bash
sudo ./uninstall.sh
```

这将移除二进制文件、配置文件和系统用户。

## 贡献

欢迎贡献！请随时提交 Pull Request。

## 许可证

MIT 许可证 - 详见`LICENSE`文件。

## 支持

有关问题、问题或贡献，请访问：
https://github.com/Amoyens1s/nodeproxy
