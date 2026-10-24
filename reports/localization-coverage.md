# 本地化覆盖报告

更新时间：2026-10-24（Asia/Shanghai）

## 资源保留

- 原项目 0.4.20+1 的 6 个官方中文 locale 文件保留；
- 原项目 227 项深度映射保留在 `source/deep-ui-zh-CN.json`；
- 原项目 0.4.20+1 Overlay 和发布哈希保持独立；
- 原有动态翻译规则、代码/命令/路径排除规则和 MutationObserver 批处理逻辑保留。

## 0.4.26+4 新增内容

- 官方 locale 新增翻译：6 项；
- 固定 UI/动态文本新增翻译：39 项；
- 0.4.26+4 映射总数：266 项；
- 新增范围：侧栏、Model Server、Library、开发者设置、聊天设置、LM Link 登录提示、运行时设置、硬件动态标签、模型搜索固定控件。

## 已验证页面

- Chat；
- Model Server；
- Library；
- Model Search；
- Settings → General；
- Settings → Appearance 导航可用；
- Settings → Developer；
- Settings → Chat；
- Settings → Model Defaults；
- Settings → Integrations；
- Settings → LM Link；
- Settings → Runtime；
- Settings → Hardware。

## 翻译边界

模型名称、远端模型简介、README、用户输入、日志、API 路径、命令和技术标识保持原文或按原项目规则处理。GUI 检查重点是固定界面文本和控件标签。

## 待人工复核

- 不同窗口尺寸下的长文本换行和极端字体缩放；
- 实际本地模型加载、推理和多轮聊天；
- 0.4.20+1 原始 Bundle 上的运行时安装回归；
- 所有下拉选项和开关的逐项交互。
