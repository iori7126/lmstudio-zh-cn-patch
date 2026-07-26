# LM Studio 简体中文深度汉化补丁

适用于 **LM Studio 0.4.20+1 / Windows x64** 的非官方简体中文增强补丁。

本项目补齐 LM Studio 官方 `zh-CN` 词库中的缺失内容，并对未进入词库的固定界面文字进行有边界的深度汉化。补丁不包含、也不分发 LM Studio 主程序。

> [!IMPORTANT]
> 补丁严格绑定 LM Studio `0.4.20+1`。其他版本会因 SHA256 不匹配而拒绝安装。

## 汉化范围

- 补齐官方中文词库缺失或空值词条 87 项；
- 增加固定硬编码界面翻译 227 项；
- 覆盖聊天、侧栏、设置、模型默认设置、运行时、硬件、LM Link、开发者页面及本地服务器；
- 支持相对日期、模型详情、下载大小等动态控件翻译；
- 保留模型名称、API 路径、参数名、代码、命令和远端动态模型介绍。

## 下载与安装

在仓库右侧 **Releases** 下载：

`LMStudio中文深度汉化补丁_0.4.20-1_deep1.1.zip`

安装步骤：

1. 完全退出 LM Studio，包括系统托盘中的进程。
2. 解压下载的 ZIP。
3. 双击 `01_install_patch.cmd`。
4. 出现 Windows 用户账户控制提示时选择“是”。
5. 启动 LM Studio，在设置中选择“简体中文”。

deep1.1 支持：

- 从官方原版直接安装；
- 从本项目早期的“中文增强补丁 v2”自动升级。

自动升级仅在当前 v2 文件及其官方原版备份均通过固定 SHA256 校验时执行。

## 恢复原版

完全退出 LM Studio，双击：

`02_restore_original.cmd`

恢复脚本会先验证备份，再以原子替换方式还原官方文件。

## 安全措施

- 安装前校验官方原文件 SHA256；
- 从 v2 迁移时同时校验 v2 文件和官方原版备份；
- 先生成候选文件并校验固定 SHA256，再修改安装目录；
- 使用同目录原子替换；
- 写入异常时从已验证备份回滚；
- LM Studio 正在运行时拒绝操作；
- 不支持的版本不会被修改。

## deep1.1 校验值

| 文件 | SHA256 |
|---|---|
| 官方原版 `main_window.js` | `5BEC77399EBD6C5C1B5426F506949C6D3202AAE0F9545B4E0BCCAB56EC7C788B` |
| 中文增强补丁 v2 | `D391E601C5E7C5E5C83E8C0D1C90311BC213CFEE0594E9C54C3A9F161A9E0FBA` |
| deep1.1 补丁后文件 | `A47D4DABEFA207A5699223B9A0BADF2CF9A29664154D8153EB6387BDEA285867` |
| deep1.1 发布 ZIP | `04CFD5F055D79FFA36BAE6FDC40548319FF4B0B3221B6FD3AEF32C295B96C7E5` |

## 已完成的验收

- 官方原版启动；
- 补丁安装及真实 Electron 界面启动；
- 聊天、设置、模型默认设置和开发者页面中文验证；
- 渲染运行时异常、控制台致命错误及加载遮罩检查；
- 关闭后重新启动；
- v2 → deep1.1 自动迁移；
- deep1.1 → 官方原版恢复；
- 缺少备份时拒绝迁移且当前文件保持不变；
- 最终 ZIP 重新解压后二次安装与恢复。

## 源码结构

- `baseline/zh-CN/`：目标版本的官方简体中文基线；
- `payload/zh-CN/`：补齐后的简体中文词库；
- `deep/deep-overlay.js`：运行时深度汉化层；
- `source/deep-ui-zh-CN.json`：深度汉化映射源；
- `source/build_deep_overlay.mjs`：深度汉化层生成脚本；
- `scripts/`：安装、校验、提权、恢复和回滚逻辑。

## 免责声明

本项目为社区非官方项目，与 LM Studio、Element Labs Inc. 无隶属、赞助或认可关系。使用前请确认 LM Studio 版本，并保留重要数据备份。

LM Studio、LM Link 及相关名称和商标归其权利人所有。

## 许可证与来源

本项目采用 [Apache License 2.0](LICENSE)。

官方本地化基线来自 [`lmstudio-ai/localization`](https://github.com/lmstudio-ai/localization)，审计提交：

`a15da90f9fbc6d714ead1f9bbe8bb8d59868877e`

详细归属说明见 [NOTICE](NOTICE)。
