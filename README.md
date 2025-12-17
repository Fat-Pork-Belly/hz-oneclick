# hz-oneclick

HorizonTech 的一键安装脚本合集。

> ⚠️ 重要说明  
> 这些脚本目前 **只在 Oracle Cloud 免费 VPS（ARM / x86）+ Ubuntu 22.04 / 24.04 上做过测试**。  
> 其它云厂商或发行版可能可以用，但需要你自己多做验证。  
> **所有脚本都视为实验性质（Experimental），请在可回滚环境中使用，并自行做好备份。**

## 仓库定位

- 为 HorizonTech 各篇教程提供「一行命令」的安装入口  
- 把共用步骤（比如 rclone、Docker、基础优化）做成可复用模块  
- 方便读者 fork 后根据自己的环境修改

示例目标（规划中）：

- Immich 部署到 VPS / OCI
- rclone 网盘挂载（OneDrive 等）
- Plex / Transmission / Tailscale / Cloudflare Tunnel 等常用组件

## 预计使用方式（规划中）

未来会提供类似命令：

```bash
bash <(curl -fsSL https://sh.horizontech.page)

```
或直接从 GitHub Raw 调用：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/hz.sh)
```

## 贡献与提交流程

- 每个步骤或独立功能对应一个 PR，保持范围小、便于 review 和回滚。
- 推荐使用前缀命名 PR 标题（如 `feat/xxx`、`fix/xxx`、`chore/xxx`、`docs/xxx` 或 `refactor/xxx`）。
- 合并前必须通过 CI 检查。
- PR 描述需严格按照模板填写，并确保 Summary、Testing 等必填项完整。

## Baseline Quick Triage

- 在「Baseline Diagnostics」菜单中新增了「Quick Triage (521/HTTPS/TLS) / 一键快排查（521/HTTPS/TLS）」入口，可一步串联 DNS/IP、Origin、防火墙、Proxy/CDN、TLS/HTTPS、LSWS/OLS、WP/App、Cache/Redis、DB、System 等检查。
- 运行时会要求输入要诊断的域名，并可选择语言（en/zh）。脚本会输出 `VERDICT`/`KEY`/`REPORT` 行，并将完整报告写入 `/tmp/hz-baseline-triage-<domain>-<YYYYmmdd-HHMMSS>.txt`（例如：`/tmp/hz-baseline-triage-abc.yourdomain.com-20240101-120000.txt`）。
- 需要求助时，请提供 `KEY:` 行和 `REPORT:` 路径，方便他人复现和定位，无需粘贴整份日志。
