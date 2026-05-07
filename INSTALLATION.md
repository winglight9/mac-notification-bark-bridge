# Mac Notification Bark Bridge

## 🚀 安装

如果你只想快速用起来，按下面 3 步做就行：

1. 打开 `MacNotificationBarkBridge.app`
2. 在系统设置里给它开 `辅助功能`
3. 在配置文件里填好 `deviceKey`

构建完成的应用位于：

- `build/MacNotificationBarkBridge.app`

如果这是自定义构建版本，macOS 可能会阻止首次打开。

推荐处理方式：

1. 在 Finder 中找到 `MacNotificationBarkBridge.app`
2. 右键应用并选择“打开”
3. 如果系统仍阻止，到 `系统设置 -> 隐私与安全性` 中手动允许

## 🔐 首次授权

应用需要以下权限才能正常工作：

1. `辅助功能`
2. 如果你启用了“登录 macOS 时自动启动”，系统可能会在 `登录项` 中显示这款应用

辅助功能入口：

- `系统设置 -> 隐私与安全性 -> 辅助功能`

首次安装时，建议按这个顺序配置：

1. 先把 `MacNotificationBarkBridge.app` 放到固定位置，再双击或右键“打开”
2. 到“辅助功能”里授权当前实际运行的那个 app
3. 打开配置文件填好 Bark `deviceKey`
4. 如果要开机自启，再在应用里勾选“登录 macOS 时自动启动”

如果你是在帮别人部署，最关键的是让他授权“实际运行的 app 路径”，不要只看文件名。

## 🖼️ 图标说明

Bark 推送的图标参数要求一个可访问的 URL。

- 应用设置页中的本地图标和应用列表，只用于帮助你识别和选择应用
- 如果你希望 Bark 推送展示指定 logo，请为对应规则填写 `图标 URL`

## 🧩 配置模型

现在的配置是“规则列表”模型：

- 每条规则可以配置多个 Bark 设备 Key
- 每条规则可以勾选多个应用
- 每条规则可以单独配置一个图标 URL
- 全局配置保留轮询间隔、去重窗口、辅助功能提示、登录启动等设置

## ⚙️ 配置文件

如果你不知道从哪里开始，先看 `config.example.jsonc`，再改 `config.json`。

程序实际读取的文件是：

- `~/Library/Application Support/MacNotificationBarkBridge/config.json`

程序还会在同目录自动放一份带详细注释和示例的参考文件：

- `~/Library/Application Support/MacNotificationBarkBridge/config.example.jsonc`

建议做法：

1. 平时只编辑 `config.json`
2. 需要查字段含义、复制示例时，打开 `config.example.jsonc`
3. 不再使用 GUI 设置界面

如果程序“打不开”或者一启动就提示配置不对，先检查这两个文件：

- 实际生效文件：`~/Library/Application Support/MacNotificationBarkBridge/config.json`
- 参考说明文件：`~/Library/Application Support/MacNotificationBarkBridge/config.example.jsonc`

一般来说，先把 `config.example.jsonc` 对照一遍，再回到 `config.json` 修正字段，最快。
