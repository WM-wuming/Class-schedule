/// 教务系统地址与**构建期**会话。
///
/// ⚠️ **这里不存任何会话值**：这个文件会被编译进产物（APK 的 `libapp.so`、
/// Web 的 `main.dart.js`），谁拿到包都能把会话翻出来。会话只走这两条路：
///
/// 1. **App 内登录**（推荐）：「我的信息」→ 学生卡片里的「登录教务系统」，
///    输学号密码换一份新会话。成功后 `JwAccountStore` 会把它连同学号一起存进
///    **本机应用私有空间**（各平台 SharedPreferences），下次启动自动带上，
///    不用再登一次；「我的信息」页可以「退出登录」清掉。
/// 2. **本地调试**：用构建参数注入，值不进仓库也不进包：
///    ```powershell
///    flutter run --dart-define=JW_COOKIE="JSESSIONID=..." --dart-define=JW_BASE_URL="https://..."
///    ```
///    构建参数**优先于**本机保存的会话，方便临时切账号。
///
/// 换学校时改下面的 `_jwBaseUrlLocal` 与模板路径，或用 `--dart-define` 覆盖。
library;

import 'package:flutter/foundation.dart' show kIsWeb;

/// 由 `--dart-define=JW_BASE_URL=...` 提供，未设置时为空字符串。
const String jwBaseUrlFromEnv = String.fromEnvironment('JW_BASE_URL');

/// 由 `--dart-define=JW_COOKIE=...` 提供，未设置时为空字符串。
const String jwCookieFromEnv = String.fromEnvironment('JW_COOKIE');

/// 教务系统主页面路径（用来读取「当前第几周 / 总周数」）。
///
/// 不同学校的模板号不一样，换学校时改这里即可（或用 `--dart-define=JW_MAIN_PAGE=...`）。
const String jwMainPagePath = String.fromEnvironment(
  'JW_MAIN_PAGE',
  defaultValue: '/framework/xsMain_new_13657.jsp?t1=1',
);

/// 学生选课中心路径（选课轮次列表）。不同学校可能不一样。
const String jwSelectionPath = String.fromEnvironment(
  'JW_SELECTION_PAGE',
  defaultValue: '/xsxk/xklc_list',
);

/// 教室空余查询路径（按周次 / 星期查教室占用表）。不同学校可能不一样。
const String jwClassroomPath = String.fromEnvironment(
  'JW_CLASSROOM_PAGE',
  defaultValue: '/kbcx/kbxx_classroom_ifr',
);

/// 教务系统根地址（到 `jsxsd` 这一层）。
const String _jwBaseUrlLocal = 'https://jw.educationgroup.cn/gzasc_jsxsd';

/// 实际使用的教务系统地址，`--dart-define` 优先。
///
/// Web 端默认走同源代理 `/jw`（浏览器不能直连跨域接口、也不能设置 Cookie 头），
/// 用 `dart run tool/jw_proxy.dart` 启动即可；也可以指定绝对地址，例如
/// `--dart-define=JW_BASE_URL=http://127.0.0.1:8765/jw`。
String get jwBaseUrl {
  if (jwBaseUrlFromEnv.isNotEmpty) {
    return jwBaseUrlFromEnv;
  }
  if (kIsWeb) {
    return '/jw';
  }
  return _jwBaseUrlLocal;
}

/// 构建参数注入的会话 Cookie：**只认 `--dart-define`，没有写死的默认值**。
///
/// 它只是一条**调试/部署用的覆盖项**，运行时会话由 [JwAccountStore] 从本机读写。
/// 两者都没有时 App 以「未登录」状态启动，提示用户去「我的信息」页登录。
String get jwCookie => jwCookieFromEnv;
