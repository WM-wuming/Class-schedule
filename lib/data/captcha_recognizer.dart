import 'captcha_recognizer_stub.dart'
    if (dart.library.io) 'captcha_recognizer_mlkit.dart' as impl;

import 'dart:typed_data';

/// 验证码识别口：把验证码图片读成人能看懂的字符串。
///
/// 抽成接口与 [KeepAlivePlatform] 同理：平台差异（ML Kit 只有 Android/iOS 有）
/// 收在实现里，测试塞假的。契约是**不抛异常** —— 识别不了返回 null，
/// 调用方退化成手动输入，登录流程不受影响。
abstract interface class CaptchaRecognizer {
  /// 识别验证码图片，返回图里的字符（原样大小写）；认不出返回 null。
  Future<String?> recognize(Uint8List imageBytes);
}

/// 按当前平台建一个识别口。
CaptchaRecognizer createCaptchaRecognizer() => impl.createCaptchaRecognizer();
