# Mac mini 外接显示器唤醒快捷键：AppleScript 刷新分辨率恢复窗口显示

适用关键词：`Mac mini 外接显示器唤醒`、`显示器断电后无信号`、`Mac mini 免拔 Type-C`、`AppleScript 刷新显示器`、`F5 恢复窗口显示`。

如果你的 `Mac mini` 一直开机，外接显示器完全断电后再开，macOS 偶尔还保留窗口状态但就是不重新出图，这个脚本就是为这个场景准备的。

它的做法很简单：

1. 用户按一次快捷键，比如 `F5`
2. 脚本把外接显示器切到临时分辨率，比如 `1024x768`
3. 等待 `1` 秒
4. 再切回原来的分辨率
5. 借此强制刷新显示输出链路，尽量避免重新插拔 `Type-C`

## 特点

- 不依赖第三方软件
- 不做后台轮询
- 只在你按下快捷键时执行
- 默认只处理外接显示器，不影响内建屏
- 可以先构建再绑定快捷键，避免第一次触发时临时编译

## 文件

- AppleScript 包装器：[scripts/refresh-external-display.applescript](/Users/quzhiyuan/Opencode/MacNotificationtoBark/scripts/refresh-external-display.applescript)
- Shell 入口：[scripts/refresh-external-display.sh](/Users/quzhiyuan/Opencode/MacNotificationtoBark/scripts/refresh-external-display.sh)
- Swift 工具源码：[scripts/refresh-external-display.swift](/Users/quzhiyuan/Opencode/MacNotificationtoBark/scripts/refresh-external-display.swift)
- 预构建脚本：[scripts/build-display-refresh-tool.sh](/Users/quzhiyuan/Opencode/MacNotificationtoBark/scripts/build-display-refresh-tool.sh)

## 配置阶段先做的事

先在终端执行一次：

```bash
./scripts/build-display-refresh-tool.sh
./scripts/refresh-external-display.sh --list
./scripts/refresh-external-display.sh --dry-run
```

这样做的目的不是后台常驻，而是把“首次编译”和“显示器模式确认”前置到配置阶段，不把这些延迟留到第一次按 `F5` 的那一刻。

这个实现不依赖辅助功能去点系统设置，所以不会把成败压在 UI 自动化权限上；真正需要前置确认的是：

- 二进制已经编译好
- 临时分辨率在你的显示器上可用
- 你要刷新的外接显示器索引是对的

## 绑定 F5

推荐用系统自带的 `Shortcuts`：

1. 打开 `快捷指令`
2. 新建一个快捷指令
3. 添加 `Run AppleScript` 动作
4. 把 [scripts/refresh-external-display.applescript](/Users/quzhiyuan/Opencode/MacNotificationtoBark/scripts/refresh-external-display.applescript) 的内容粘进去
5. 在快捷指令详情里设置键盘快捷键为 `F5`

推荐直接把脚本文本粘进 `Run AppleScript` 动作里运行，而不是依赖终端里 `osascript some-file.applescript` 这种文件执行方式。前者在日常使用里更稳定，也更符合“配置阶段先准备好、触发时只执行刷新”的目标。

如果你有多块外接显示器，可以把 AppleScript 最后一行改成带参数版本，比如：

```applescript
do shell script quoted form of runnerPath & " --display-index 2"
```

## 常用命令

列出当前在线显示器和模式：

```bash
./scripts/refresh-external-display.sh --list
```

只看会切到什么模式，不实际执行：

```bash
./scripts/refresh-external-display.sh --dry-run
```

指定临时分辨率和延迟：

```bash
./scripts/refresh-external-display.sh --temp-width 1280 --temp-height 720 --delay 1.2
```

## 边界说明

- 如果显示器已经被 macOS 彻底判定为离线，软件就拿不到这个输出口，脚本也无从切换分辨率
- 某些显示器不支持 `1024x768`，脚本会自动选一个最接近的可用临时模式
- 切换分辨率时会有一次短暂闪屏，这是预期行为

## 一句话总结

这是一个给 `Mac mini 外接显示器断电后不亮` 场景准备的快捷键刷新脚本，用 `AppleScript + Swift + 系统自带命令` 强制刷新显示信号，目标是少拔一次线。
