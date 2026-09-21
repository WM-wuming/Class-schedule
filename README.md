# 广应科课表

仿照移动端课程表 App 的界面，用 **Flutter + forui 0.26** 实现。
课表数据从**正方教务系统**（`xskb/xskb_list.do`）获取：整学期总课表解析成 **JSON 快照存在本机**，
界面从快照加载，缺周或手动刷新时才重新联网；
「用户自己添加的课程」与几项本机设置（账户、提醒、保活）同样落盘 —— 那是用户数据。

![Web 端实拍（真实教务系统数据）](docs/web-preview.png)

![选课页（真实教务系统）](docs/web-selection.png)

## 软件功能

### 课表

- 四页主框架：**课表 / 教室详细 / 选课 / 我的信息**（底部导航，Web 端 hash 直达）
- **整学期总课表本地化**：用课表接口逐周拉取后合并成 JSON 快照落盘；冷启动先读快照，切任何一周都从本地加载、秒开零请求；快照缺周、登录新账号或下拉刷新时才重新联网补全
- 节次网格自绘：周日→周六表头、节次时间轴、**午休/晚休分隔行**、彩色课程卡片（按课程名稳定取色）、今天高亮
- 左右滑动翻周、周次胶囊直接跳周/回到本周、相邻周自动预取、连续快滑防抖（最多 3 个请求）
- 网格随系统字号等比缩放（0.85~1.6 限幅）；设置里可选显示周末/教师/节次时间、淡化非本周课程
- 右上角刷新按钮一键重新拉课表；加载失败降级为提示条
- **「放假啦」彩蛋**：滑到学期最后一周再往后翻出现放假页，再翻回第 1 周

### 课程

- **点课程弹居中玻璃卡详情**：上课时间（钟点区间）、地点、教师、周次、属性/学分、本周是否上课
- **自建课程**：右下角加号添加教务系统里没有的课（自习/社团/调课），可编辑删除；参与提醒、小组件与课时统计；刷新/换账号/退出登录都不动它

### 上课提醒与保活

- **上课提醒**：总开关 + 提前量（5~60 分钟），通知随课表排期（覆盖式重排、内容没变不碰闹钟、过点不补发）；提醒窗口过后打开 App 会**自动往下拉新课表补排提醒**
- **保活栏目**：开机自启指引（按机型跳系统自启动管理）+ 后台耗电限制取消分步指引（申请电池优化白名单）
- **桌面小组件**：2×1「下一节课/正在上课」卡片，没课显示「没有课了可以放心玩了！」；课表变化即时推、节次边界闹钟换内容、30 分钟兜底轮询

### 登录与账号

- 应用内**登录教务系统**：学号 + 密码 + 验证码；**验证码本机离线识别（ML Kit）、自动填入并自动提交，识别错了自动换图重试（最多 3 次），也可手动输入**；验证码失败自动换图、失败原因保留；**记住密码**可选项（本机私有空间，下次免输密码）；退出登录二次确认并清空一切
- 我的信息页展示姓名/学号/院系/专业/班级（与当前周次同一响应，零额外请求）
- 周次与开学日期按教务系统主页面自动校准，学期兜底值可被纠正

### 查询（只读）

- **教室详细**：按日期/校区/教学楼查教室占用一览（红绿小条，按上午/下午/晚上分组），点教室弹出当天每节课的上课班级与空闲时段
- **选课**：学生选课中心的轮次列表（只读，不提交志愿）

### 界面质感

- 全部底部弹层与居中弹窗统一**液态玻璃**质感：弹层本体毛玻璃卡，弹出时整个背景磨砂模糊+轻压暗（动画跟随）
- 沉浸式 edge-to-edge：页面头部延伸到状态栏底下，状态栏图标随页面深浅自动变色

## 构建所需环境

### 基础工具链

| 组件 | 要求 |
| --- | --- |
| Flutter SDK | ≥ 3.38（Dart SDK `^3.13.4`，见 `pubspec.yaml`） |
| JDK | 17+（本机用 LibericaJDK-25） |
| Android SDK | compileSdk 36 / build-tools 36.0.0 / platform-tools，`ANDROID_HOME` 指向 SDK 根目录 |
| 运行平台 | Android 7.0+（`minSdkVersion` 24）；Web 端需配合同源网关（`tool/jw_proxy.dart`） |

主要依赖：`forui`（界面外壳）、`web`、`shared_preferences`（账户/设置落盘）、
`flutter_local_notifications` + `timezone`（上课提醒）。

### 构建命令

```powershell
flutter pub get
flutter test                      # 全部测试（联网实测默认跳过）

# Android APK（需先设置 SDK 路径）
$env:ANDROID_HOME='D:\pata'; $env:ANDROID_SDK_ROOT='D:\pata'
flutter build apk --release       # → build\app\outputs\flutter-apk\app-release.apk

# Web（附带跨域解决方案）
flutter build web --release
dart run tool/jw_proxy.dart       # 打开 http://127.0.0.1:8765/
```

### Android 构建配置要点

| 项 | 值 | 说明 |
| --- | --- | --- |
| `minSdkVersion` | 24 | Android 7.0+ |
| `targetSdkVersion` | 36 | 面向新系统优化，不影响老设备运行 |
| native-code | arm64-v8a / armeabi-v7a / x86_64 | 覆盖主流真机与模拟器 |
| 网络 | 仅 HTTPS | Android 9 默认禁止明文 HTTP，本项目只访问 `https://` 教务系统 |
| 签名 | 自备 release 密钥库 | `android/key.properties` + `android/release-keystore.jks`（均已 gitignore）；文件缺失时自动退回 debug 签名，`flutter run --release` 仍可用 |

`flutter_local_notifications` 要求宿主也开 **core library desugaring**，缺了会报
`:app:checkReleaseAarMetadata` 失败，`android/app/build.gradle.kts` 里两处缺一不可：

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        // ...
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

上课提醒相关权限（都在 `android/app/src/main/AndroidManifest.xml`，改完务必用
`aapt2 dump badging` 复核）：`POST_NOTIFICATIONS`（13+ 运行时申请）、
`SCHEDULE_EXACT_ALARM`（准点响，拿不到退化成不精确排期）、`RECEIVE_BOOT_COMPLETED`
（重启后重新登记提醒），以及 `flutter_local_notifications` 要求显式声明的两个
`exported=false` 接收器（`ScheduledNotificationReceiver` / `ScheduledNotificationBootReceiver`）。

### 国内网络绕行

1. **pub 依赖走国内镜像**：
   ```powershell
   $env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
   $env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
   ```
2. **Gradle 依赖走阿里云**：`~/.gradle/init.gradle`（init 脚本用 `beforeSettings` 注入
   `pluginManagement` 镜像并加到每个 project，`repositoriesMode` 设为 `PREFER_PROJECT`）。
3. **Gradle 发行版走腾讯镜像**：`android/gradle/wrapper/gradle-wrapper.properties`
   已改为 `https://mirrors.cloud.tencent.com/gradle/gradle-9.3.1-all.zip`。
4. **关掉 AGP 自动下载 SDK 组件**：`android/gradle.properties` 里
   `android.builder.sdkDownload=false`，缺组件时立刻报错指出包名，按提示从镜像装即可。

其它工程约定（Gradle 侧）：`kotlin.incremental=false`（跨盘符增量编译会崩，勿删）。
冷编译约 10 分钟，之后改 Dart 代码再打包约 1 分钟。
