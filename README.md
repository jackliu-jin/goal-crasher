# Goal Crasher 闯场之王 — Godot 4 版

把原 HTML5/Canvas 版用 **Godot 4** 重写：保留像素风角色，叠加 Godot 引擎的润色——
**相机平滑跟随 + 缩放、震屏、辉光/泛光环境、像素精灵运行时生成、底部体力/狂热槽、全屏闪光、纸屑**。

在线试玩（CI 自动构建后）：**https://jackliu-jin.github.io/goal-crasher/**

---

## 一、本地运行（Godot 编辑器）

1. 启动 Godot 4.7，项目管理器 → **Import** → 选本文件夹的 `project.godot` → **Import & Edit**。
2. 按 **F5** 运行。
3. 操作：WASD 移动 / Shift 冲刺 / 空格 翻滚；移动端左摇杆 + 右按钮。

## 二、网页版自动构建 + 部署（GitHub Actions → Pages）

本仓库已内置 `.github/workflows/deploy.yml`：每次 push 到 `main`，云端会用 Godot 无头模式
导出 HTML5 并自动发布到 GitHub Pages。**你只管改代码、push，网页版会自动更新。**

### 首次启用步骤
1. 仓库已创建并推送（`goal-crasher`）。
2. 在 GitHub 仓库 **Settings → Pages → Build and deployment → Source** 选 **GitHub Actions**
   （若用脚本已设为 workflow 则无需手动设）。
3. 打开 **Actions** 标签页，看 “Build & Deploy Web” 工作流是否绿灯。
4. 成功后访问 https://jackliu-jin.github.io/goal-crasher/ ，手机浏览器也能玩。

### ⚠️ 版本要对齐
工作流顶部有一行 `GODOT_VERSION: "4.7-stable"`。
请确认它和你本地 Godot 版本一致（Godot **帮助 → 关于** 里看精确版本）：
- 例如你的是 `4.7.1`，就改成 `"4.7.1-stable"`；是 `4.4`，就改成 `"4.4-stable"`。
- 不一致会导致云端下载不到对应引擎/导出模板而构建失败。

### 为什么网页版导出关掉了「线程支持」
GitHub Pages 无法发送 Godot 多线程 Web 构建所需的跨源隔离响应头（COOP/COEP），
所以 `export_presets.cfg` 里 `variant/thread_support=false`。本游戏是单线程，关掉无影响。

## 三、手动导出（备用，不走 CI 时）

Godot 编辑器 → **Project → Export → Add → Web** → 取消勾选 **Thread Support** →
**Export Project** 到 `build/index.html`，把 `build/` 里所有文件传到能托管静态页面的地方即可。

---

## 四、项目结构

```
goal-crasher/
├── project.godot              项目配置
├── Main.tscn                  主场景（挂 Game.gd 的根节点）
├── Game.gd                    全部逻辑 + 渲染 + UI（单文件）
├── export_presets.cfg         Web 导出预设（线程关闭，适配 Pages）
├── icon.svg                   图标
├── .github/workflows/deploy.yml  自动构建+部署到 Pages
└── README.md
```

## 五、调数值

`Game.gd` 顶部 `TUNE` 字典集中了惯性、速度、体力等参数；合影半径、飞扑时长、保安数量公式
等也都在脚本里，改完按 F5 或 push 触发重新构建即可。

## 六、已实现机制

玩家移动惯性 / 冲刺 / 翻滚无敌帧 / 体力力竭；球员全员逃跑 + 体力槽（球星更难抓）+ 无限补充；
保安寻路追击 + 蓄力飞扑三段式 + 尸海 + 精英预判；暴动时间引开保安；Roguelite 升级二选一 + 无尽阈值；
写实球场标线 + 可走动跑道；相机缩放/震屏、辉光、像素跑动弹跳、纸屑、解说、危机泛红。
