import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../state/schedule_controller.dart';
import '../theme/course_palette.dart';

/// 登录教务系统：用学号密码换一份新会话。
///
/// 为什么需要它：App 里原来烘焙着一份会话 Cookie，它会过期，过期后只能改代码重新打包。
/// 有了这一页，遇到「会话已失效」时用户自己输账号密码就能恢复。
///
/// 登进来之后：会话连同学号一起由 `JwAccountStore` 存进本机应用私有空间，
/// **下次打开就不用再登一次**；密码只有用户勾选「记住密码」才一并保存（同样只为
/// 免输，教务系统有一次性验证码，拿着密码也没法自动重登）。
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.initialAccount = '',
    this.initialPassword = '',
  });

  /// 预填的学号 / 账号：本机存过就直接填上，省得每次手打。
  final String initialAccount;

  /// 预填的密码：用户勾过「记住密码」才有，同时决定开关的初始状态。
  final String initialPassword;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _account = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _captcha = TextEditingController();
  bool _showPassword = false;

  /// 「记住密码」勾选状态：本机存过密码就默认勾上。
  bool _remember = false;

  @override
  void initState() {
    super.initState();
    _account.text = widget.initialAccount;
    _password.text = widget.initialPassword;
    _remember = widget.initialPassword.isNotEmpty;
    // 进页面就先要一张验证码。放到帧后是因为 [ScheduleController.startLogin]
    // 会立刻 notifyListeners，不能在 build 期间改状态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScheduleScope.of(context).startLogin();
      }
    });
  }

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    _captcha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);
    final bool loading = controller.loginLoading;
    final bool hasCaptcha = controller.captchaImage != null;
    final bool filled =
        _account.text.trim().isNotEmpty &&
        _password.text.isNotEmpty &&
        _captcha.text.trim().isNotEmpty;
    final String? error = controller.loginError;

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: const Text(
          '登录教务系统',
          style: TextStyle(
            color: GridColors.textPrimary,
            fontSize: 17,
            height: 1.1,
            fontWeight: FontWeight.w600,
          ),
        ),
        prefixes: <Widget>[
          FHeaderAction(
            icon: const Icon(FLucideIcons.chevronLeft, size: 20),
            onPress: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: <Widget>[
          const _HintCard(),
          const SizedBox(height: 20),
          FTextField(
            control: FTextFieldControl.managed(
              controller: _account,
              onChange: (_) => setState(() {}),
            ),
            label: const Text('学号 / 账号'),
            hint: '教务系统的登录账号',
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          FTextField(
            control: FTextFieldControl.managed(
              controller: _password,
              onChange: (_) => setState(() {}),
            ),
            label: const Text('密码'),
            hint: '教务系统的登录密码',
            obscureText: !_showPassword,
            textInputAction: TextInputAction.next,
            suffixBuilder:
                (BuildContext context, FTextFieldStyle style, Set<FTextFieldVariant> variants) =>
                    FButton.icon(
                      variant: .ghost,
                      onPress: () =>
                          setState(() => _showPassword = !_showPassword),
                      child: Icon(
                        _showPassword ? FLucideIcons.eyeOff : FLucideIcons.eye,
                        size: 16,
                      ),
                    ),
          ),
          const SizedBox(height: 4),
          // 「记住密码」：勾上后本次登录成功就把密码存进本机（登录页免输一遍）；
          // 不勾则什么都不存，还会把之前存的抹掉。
          _RememberPasswordTile(
            value: _remember,
            onChanged: (bool next) => setState(() => _remember = next),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: FTextField(
                  control: FTextFieldControl.managed(
                    controller: _captcha,
                    onChange: (_) => setState(() {}),
                  ),
                  label: const Text('验证码'),
                  hint: '右侧图片里的字符',
                  textInputAction: TextInputAction.done,
                ),
              ),
              const SizedBox(width: 12),
              _CaptchaImage(
                bytes: controller.captchaImage,
                loading: loading,
                onRefresh: () {
                  _captcha.clear();
                  controller.startLogin();
                },
              ),
            ],
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: 16),
            _ErrorBanner(
              message: error,
              // 登录失败后验证码已经自动换过一张了，说一句 —— 不然用户下次抬眼
              // 发现图变了，会以为是自己看花了眼。
              hint: hasCaptcha ? '验证码已自动更换，请重新输入' : null,
            ),
          ],
          const SizedBox(height: 22),
          FButton(
            onPress: loading || !hasCaptcha || !filled
                ? null
                : () => _submit(controller),
            child: Text(loading ? '请稍候…' : '登录'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FButton(
              variant: .ghost,
              onPress: loading ? null : controller.startLogin,
              child: const Text('换一张验证码'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(ScheduleController controller) async {
    final bool ok = await controller.submitLogin(
      account: _account.text.trim(),
      password: _password.text,
      captcha: _captcha.text.trim(),
      rememberPassword: _remember,
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      // 会话已经换掉了，回到「我的信息」就能看到新账号的姓名学号。
      Navigator.of(context).maybePop();
      return;
    }
    // 验证码被服务端消耗掉了，清空输入等用户重新辨认新的一张。
    _captcha.clear();
  }
}

/// 验证码图片：点一下换一张。
class _CaptchaImage extends StatelessWidget {
  const _CaptchaImage({
    required this.bytes,
    required this.loading,
    required this.onRefresh,
  });

  final Uint8List? bytes;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final Uint8List? image = bytes;
    return GestureDetector(
      onTap: loading ? null : onRefresh,
      child: Container(
        width: 100,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: GridColors.gutter,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: GridColors.divider),
        ),
        child: image == null
            ? Text(
                loading ? '加载中…' : '点此获取',
                style: const TextStyle(
                  color: GridColors.textSecondary,
                  fontSize: 12,
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                // gaplessPlayback：换一张时不要先闪成空白
                child: Image.memory(
                  image,
                  width: 96,
                  height: 38,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
      ),
    );
  }
}

/// 「记住密码」一行：勾上后登录成功就把密码存进本机，登录页免输一遍。
///
/// 用 [_RememberPasswordTile] 而不是 FTile：登录页是普通 ListView 排版，
/// 一个紧凑的自绘行比整套 tile 组更贴合这里的密度。
class _RememberPasswordTile extends StatelessWidget {
  const _RememberPasswordTile({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    // forui 的 FScaffold 不提供 Material 祖先，InkWell/Checkbox 都要；
    // 透明 Material 只补类型不画底色。
    type: MaterialType.transparency,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                // 勾选本身就要触发 setState 重建（提交时读 [_remember]），不归控制器管。
                onChanged: (bool? next) => onChanged(next ?? false),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              '记住密码',
              style: TextStyle(
                color: GridColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '仅保存在本机，登录仍需输入验证码',
                style: TextStyle(
                  color: GridColors.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 顶部说明卡片。
class _HintCard extends StatelessWidget {
  const _HintCard();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFF3F7FE),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFD8E4F8)),
    ),
    child: const Padding(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(FLucideIcons.info, size: 16, color: GridColors.today),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '会话过期后，在这里用学号密码重新登录即可。\n'
              '登录成功后会话与学号保存在本机，下次打开不用再登；'
              '勾选「记住密码」可以把密码也存在本机（登录时免输，仍要输验证码），'
              '不勾就完全不落盘。随时可在「我的信息」页退出登录。',
              style: TextStyle(color: Color(0xFF3A4A66), fontSize: 12.5),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 登录失败时的提示条（文案来自教务系统）。
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.hint});

  final String message;

  /// 附加第二行说明，比如「验证码已自动更换」。null 表示不显示。
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final String? tip = hint;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF0D9A8)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(FLucideIcons.info, size: 16, color: Color(0xFFB7791F)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    message,
                    style: const TextStyle(
                      color: Color(0xFF8A6116),
                      fontSize: 12.5,
                    ),
                  ),
                  if (tip != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      tip,
                      style: const TextStyle(
                        color: Color(0xFF9A7A44),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
