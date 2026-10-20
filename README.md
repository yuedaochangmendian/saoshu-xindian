# 扫书新典

离线 Android 扫书资料阅读器，界面参考“扫书宝典”的青绿色卡片、粉红色搜索栏与底部导航。

## 下载

GitHub Release 提供：

- `扫书新典-v1.0.apk`：已签名、可直接安装的 Android 应用
- `扫书新典-source.zip`：完整源码、在线数据库与构建配置

## 数据

- `app/src/main/assets/saoshu.db`：75,176 条内容、27,153 个书名聚合、75,747 次来源关系
- 数据截止：2026-10-20
- 正文完整保留；标题、作者、书名建立本地索引，正文检索在需要时执行

数据库文件约 169 MB，超过 GitHub 对单个普通仓库文件 100 MB 的限制，因此不提交到 Git 历史，而是放在 Release 的完整源码压缩包中。克隆源码后，将 `saoshu.db` 放入 `app/src/main/assets/` 即可构建。

## 功能

- 首页统计、类型快捷入口和最近收录
- 标题、作者、书名搜索，标题无结果时自动回退正文检索
- 分类与来源筛选
- 书名聚合、相关评论与楼内回复阅读
- 收藏、复制正文、打开原帖、多来源记录
- 上一篇/下一篇

## 构建

需要 JDK 17+、Android SDK Platform 35 和 Build-Tools 35。

```powershell
gradle --offline assembleDebug
```

APK 输出在 `app/build/outputs/apk/debug/app-debug.apk`。首次启动会把离线数据库复制到应用私有目录，随后完全离线运行。

## 技术栈

- Java / Android 原生 View
- SQLite 内置离线数据库
- FTS4 标题、作者与书名索引
- 无第三方运行时依赖
