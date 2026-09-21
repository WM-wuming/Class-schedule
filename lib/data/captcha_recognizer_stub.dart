import 'dart:typed_data';

import 'captcha_recognizer.dart';

/// 无识别能力的桩（Web 等平台）：永远返回 null，登录页退化成手动输入。
class NoopCaptchaRecognizer implements CaptchaRecognizer {
  @override
  Future<String?> recognize(Uint8List imageBytes) async => null;
}

CaptchaRecognizer createCaptchaRecognizer() => NoopCaptchaRecognizer();
