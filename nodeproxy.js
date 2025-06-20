#!/usr/bin/env bun

import { createServer as createHttpsServer } from "https";
import { request as httpRequest, createServer as createHttpServer } from "http";
import { connect as netConnect } from "net";
import { parse as urlParse } from "url";
import { readFileSync, existsSync } from "fs";
import { join } from "path";
import { Server } from "tls";

// 配置文件路径
const CONFIG_PATHS = [
  "/etc/nodeproxy/config.json",
  join(process.cwd(), "config.json"),
  join(import.meta.dir, "config.json"),
];

// 默认配置
const DEFAULT_CONFIG = {
  port: 8443,
  host: "0.0.0.0",
  auth: {
    enabled: true,
    username: "admin",
    password: "changeme",
  },
  ssl: {
    cert: "/etc/nodeproxy/ssl/cert.pem",
    key: "/etc/nodeproxy/ssl/key.pem",
  },
  logging: {
    level: "info",
    timestamp: true,
  },
  timeout: 30000,
};

// 日志级别
const LOG_LEVELS = {
  error: 0,
  warn: 1,
  info: 2,
  debug: 3,
};

class ProxyServer {
  constructor(config) {
    this.config = { ...DEFAULT_CONFIG, ...config };
    this.logLevel = LOG_LEVELS[this.config.logging.level] || LOG_LEVELS.info;
  }

  log(level, message) {
    if (LOG_LEVELS[level] <= this.logLevel) {
      const timestamp = this.config.logging.timestamp
        ? `[${new Date().toISOString()}] `
        : "";
      console.log(`${timestamp}[${level.toUpperCase()}] ${message}`);
    }
  }

  authenticate(authHeader) {
    if (!this.config.auth.enabled) return true;

    if (!authHeader || !authHeader.startsWith("Basic ")) {
      return false;
    }

    try {
      const credentials = Buffer.from(authHeader.slice(6), "base64").toString();
      const [username, password] = credentials.split(":", 2);
      return (
        username === this.config.auth.username &&
        password === this.config.auth.password
      );
    } catch (error) {
      return false;
    }
  }

  sendAuthError(res) {
    res.writeHead(407, {
      "Proxy-Authenticate": 'Basic realm="Proxy Server"',
      "Content-Type": "text/plain",
      "Content-Length": "32",
      Connection: "close",
    });
    res.end("Proxy Authentication Required");
  }

  sendError(res, statusCode, message) {
    res.writeHead(statusCode, {
      "Content-Type": "text/plain",
      "Content-Length": Buffer.byteLength(message),
      Connection: "close",
    });
    res.end(message);
  }

  loadCertificates() {
    try {
      const key = readFileSync(this.config.ssl.key, "utf8");
      const cert = readFileSync(this.config.ssl.cert, "utf8");
      this.log("info", "SSL certificates loaded successfully");
      return { key, cert };
    } catch (error) {
      this.log("error", `Failed to load SSL certificates: ${error.message}`);
      throw error;
    }
  }

  handleHttpRequest(req, res) {
    // 检查认证
    if (this.config.auth.enabled) {
      const authHeader = req.headers["proxy-authorization"];
      if (!this.authenticate(authHeader)) {
        this.log(
          "warn",
          `Authentication failed: ${req.method} ${req.url} from ${req.socket.remoteAddress}`
        );
        this.sendAuthError(res);
        return;
      }
    }

    this.log(
      "info",
      `Proxy request: ${req.method} ${req.url} (HTTP/${req.httpVersion})`
    );

    try {
      const urlParts = urlParse(req.url);

      // 构建目标请求选项
      const options = {
        hostname: urlParts.hostname,
        port: urlParts.port || (urlParts.protocol === "https:" ? 443 : 80),
        path: urlParts.path,
        method: req.method,
        headers: { ...req.headers },
        timeout: this.config.timeout,
        rejectUnauthorized: false,
      };

      // 清理代理相关的头部
      delete options.headers["proxy-authorization"];
      delete options.headers["proxy-connection"];
      options.headers["host"] = urlParts.hostname;

      // 创建请求函数
      const makeRequest = (protocol, options, callback) => {
        if (protocol === "https:") {
          return import("https").then((module) =>
            module.request(options, callback)
          );
        } else {
          return import("http").then((module) =>
            module.request(options, callback)
          );
        }
      };

      // 发起请求
      makeRequest(urlParts.protocol, options, (proxyRes) => {
        this.log(
          "debug",
          `Target server response: ${proxyRes.statusCode} (HTTP/${
            proxyRes.httpVersion || "unknown"
          })`
        );

        // 设置响应头
        res.writeHead(proxyRes.statusCode, proxyRes.headers);

        // 转发响应数据
        proxyRes.pipe(res);

        proxyRes.on("end", () => {
          this.log(
            "debug",
            `Request completed: ${req.method} ${req.url} -> ${proxyRes.statusCode}`
          );
        });
      })
        .then((proxyReq) => {
          // 错误处理
          proxyReq.on("error", (err) => {
            this.log(
              "error",
              `Proxy request error: ${err.message} (${req.url})`
            );
            if (!res.headersSent) {
              this.sendError(res, 502, "Bad Gateway");
            }
          });

          proxyReq.on("timeout", () => {
            this.log("error", `Proxy request timeout: ${req.url}`);
            proxyReq.destroy();
            if (!res.headersSent) {
              this.sendError(res, 504, "Gateway Timeout");
            }
          });

          // 转发请求数据
          req.pipe(proxyReq);

          // 处理客户端断开连接
          req.on("close", () => {
            proxyReq.destroy();
          });
        })
        .catch((error) => {
          this.log("error", `Error creating request: ${error.message}`);
          if (!res.headersSent) {
            this.sendError(res, 500, "Internal Server Error");
          }
        });
    } catch (error) {
      this.log("error", `Error handling request: ${error.message}`);
      if (!res.headersSent) {
        this.sendError(res, 500, "Internal Server Error");
      }
    }
  }

  handleConnect(req, clientSocket, head) {
    // 检查认证
    if (this.config.auth.enabled) {
      const authHeader = req.headers["proxy-authorization"];
      if (!this.authenticate(authHeader)) {
        this.log(
          "warn",
          `CONNECT authentication failed: ${req.url} from ${clientSocket.remoteAddress}`
        );
        clientSocket.write("HTTP/1.1 407 Proxy Authentication Required\r\n");
        clientSocket.write(
          'Proxy-Authenticate: Basic realm="Proxy Server"\r\n'
        );
        clientSocket.write("Connection: close\r\n");
        clientSocket.write("\r\n");
        clientSocket.end();
        return;
      }
    }

    this.log("info", `CONNECT request: ${req.url}`);

    try {
      const [hostname, port] = req.url.split(":");
      const targetPort = parseInt(port) || 443;

      // 连接到目标服务器
      const serverSocket = netConnect(targetPort, hostname, () => {
        // 发送连接成功响应
        clientSocket.write("HTTP/1.1 200 Connection Established\r\n");
        clientSocket.write("Connection: keep-alive\r\n");
        clientSocket.write("\r\n");

        // 转发初始数据
        if (head && head.length > 0) {
          serverSocket.write(head);
        }

        // 建立双向数据流
        serverSocket.pipe(clientSocket, { end: false });
        clientSocket.pipe(serverSocket, { end: false });

        this.log("debug", `CONNECT tunnel established: ${req.url}`);
      });

      // 错误处理
      serverSocket.on("error", (err) => {
        this.log("error", `CONNECT error: ${err.message} (${req.url})`);
        if (!clientSocket.destroyed) {
          clientSocket.write("HTTP/1.1 502 Bad Gateway\r\n");
          clientSocket.write("Connection: close\r\n");
          clientSocket.write("\r\n");
          clientSocket.end();
        }
      });

      clientSocket.on("error", (err) => {
        this.log("debug", `Client connection error: ${err.message}`);
        if (!serverSocket.destroyed) {
          serverSocket.destroy();
        }
      });

      // 处理连接关闭
      serverSocket.on("close", () => {
        if (!clientSocket.destroyed) {
          clientSocket.end();
        }
      });

      clientSocket.on("close", () => {
        if (!serverSocket.destroyed) {
          serverSocket.destroy();
        }
      });
    } catch (error) {
      this.log("error", `Error handling CONNECT request: ${error.message}`);
      if (!clientSocket.destroyed) {
        clientSocket.write("HTTP/1.1 500 Internal Server Error\r\n");
        clientSocket.write("Connection: close\r\n");
        clientSocket.write("\r\n");
        clientSocket.end();
      }
    }
  }

  async start() {
    this.log("info", "Starting HTTP/2 forward proxy server with Bun...");

    // 加载SSL证书
    const certificates = this.loadCertificates();

    // SSL配置
    const serverOptions = {
      key: certificates.key,
      cert: certificates.cert,
      ALPNProtocols: ["h2", "http/1.1"],
    };

    // 创建HTTPS服务器
    this.server = createHttpsServer(serverOptions, (req, res) => {
      this.handleHttpRequest(req, res);
    });

    // 监听CONNECT事件
    this.server.on("connect", (req, socket, head) => {
      this.handleConnect(req, socket, head);
    });

    // SSL错误处理
    this.server.on("tlsClientError", (err, tlsSocket) => {
      this.log("error", `TLS client error: ${err.message}`);
    });

    // 一般错误处理
    this.server.on("error", (err) => {
      this.log("error", `Server error: ${err.message}`);
      if (err.code === "EADDRINUSE") {
        this.log("error", `Port ${this.config.port} is already in use`);
      }
      process.exit(1);
    });

    // 启动服务器
    this.server.listen(this.config.port, this.config.host, () => {
      this.log("info", "=".repeat(60));
      this.log("info", "HTTP/2 Forward Proxy Server Started (Powered by Bun)");
      this.log(
        "info",
        `Listening on: ${this.config.host}:${this.config.port} (HTTPS)`
      );
      if (this.config.auth.enabled) {
        this.log("info", `Authentication: Enabled`);
      }
      this.log("info", "=".repeat(60));
    });

    // 优雅关闭
    process.on("SIGINT", () => this.shutdown());
    process.on("SIGTERM", () => this.shutdown());

    // 处理重载信号（用于证书更新）
    process.on("SIGHUP", () => {
      this.log("info", "Received reload signal, reloading certificates...");
      try {
        const certificates = this.loadCertificates();
        this.server.setSecureContext({
          key: certificates.key,
          cert: certificates.cert,
        });
        this.log("info", "Certificates reloaded successfully");
      } catch (error) {
        this.log("error", `Failed to reload certificates: ${error.message}`);
      }
    });

    // 全局错误处理
    process.on("uncaughtException", (err) => {
      this.log("error", `Uncaught exception: ${err.message}`);
      console.error(err.stack);
      process.exit(1);
    });

    process.on("unhandledRejection", (reason, promise) => {
      this.log("error", `Unhandled promise rejection: ${reason}`);
      console.error("Promise:", promise);
      process.exit(1);
    });
  }

  shutdown() {
    this.log("info", "Shutting down server...");
    this.server.close(() => {
      this.log("info", "Server closed");
      process.exit(0);
    });
  }
}

// 加载配置文件
function loadConfig() {
  for (const configPath of CONFIG_PATHS) {
    try {
      if (existsSync(configPath)) {
        const configData = readFileSync(configPath, "utf8");
        const config = JSON.parse(configData);
        console.log(`Configuration loaded from: ${configPath}`);
        return config;
      }
    } catch (error) {
      console.error(`Error loading config from ${configPath}:`, error.message);
    }
  }

  console.log("No configuration file found, using defaults");
  return {};
}

// 主函数
if (import.meta.main) {
  const config = loadConfig();
  const server = new ProxyServer(config);
  server.start();
}

export default ProxyServer;
