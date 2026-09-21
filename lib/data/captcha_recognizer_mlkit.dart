import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'captcha_recognizer.dart';

/// ML Kit 本地文字识别实现的验证码识别（离线，不联网）。
///
/// 本校教务的验证码是白底 + 4 个彩色衬线字符、几乎无干扰线，
/// ML Kit 的拉丁文识别模型直接就能读对；偶尔读错也没关系 ——
/// 调用方（登录流程）识别失败/校验失败会自动换图重试。
///
/// 图片通过**内存字节**（Android: NV21 / iOS: BGRA8888）直接喂给 ML Kit，
/// 不经过临时文件 —— 早期版本走 `InputImage.fromFilePath` + `Directory.systemTemp`，
/// 在部分真机上静默失败（表现为验证码永远识别不出来），改内存方案绕开它。
class MlKitCaptchaRecognizer implements CaptchaRecognizer {
  /// ML Kit 插件只有 Android/iOS 实现，其它平台（桌面/Web）直接认输。
  static bool get _platformSupported => Platform.isAndroid || Platform.isIOS;

  /// 识别器很重（加载模型），进程内只建一个、反复用。
  static TextRecognizer? _shared;

  /// 最近一次识别失败的原因（识别成功或尚未跑过为 null）。
  ///
  /// 识别契约不抛异常，但完全吞掉失败会让「为什么没自动填」无从查起；
  /// 登录页会把它拼进提示里，方便用户反馈。
  static String? lastError;

  TextRecognizer get _recognizer =>
      _shared ??= TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<String?> recognize(Uint8List imageBytes) async {
    lastError = null;
    if (!_platformSupported || imageBytes.isEmpty) {
      return null;
    }
    try {
      final (int width, int height, Uint8List pixels) = await _decodeScaledRgba(
        imageBytes,
      );
      final InputImage image = Platform.isAndroid
          ? InputImage.fromBytes(
              bytes: _rgbaToNv21(pixels, width, height),
              metadata: InputImageMetadata(
                size: ui.Size(width.toDouble(), height.toDouble()),
                rotation: InputImageRotation.rotation0deg,
                format: InputImageFormat.nv21,
                bytesPerRow: width,
              ),
            )
          : InputImage.fromBytes(
              bytes: _rgbaToBgra(pixels),
              metadata: InputImageMetadata(
                size: ui.Size(width.toDouble(), height.toDouble()),
                rotation: InputImageRotation.rotation0deg,
                format: InputImageFormat.bgra8888,
                bytesPerRow: width * 4,
              ),
            );
      final RecognizedText result = await _recognizer.processImage(image);
      final String cleaned = _alphanumeric(result.text);
      return cleaned.isEmpty ? null : cleaned;
    } catch (error) {
      // 识别不了（插件缺失 / 模型没装好 / 图片坏）就当没识别过，
      // 登录页退化成手动输入；原因留在这里供界面提示与排查。
      lastError = error.toString();
      return null;
    }
  }

  /// 把验证码图解码并放大，返回 RGBA 像素。
  ///
  /// ML Kit 对太小的图（原图约 60×22）检测不到文字，放大约 4 倍后稳得多。
  /// 宽高都取偶数：NV21 的色度平面按 2×2 下采样，奇数宽会错位。
  Future<(int, int, Uint8List)> _decodeScaledRgba(Uint8List imageBytes) async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      imageBytes,
    );
    final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
      buffer,
    );
    final int targetWidth = math.max(320, descriptor.width * 4) & ~1;
    final int targetHeight =
        math.max(
          1,
          (descriptor.height * targetWidth / descriptor.width).round(),
        ) &
        ~1;
    final ui.Codec codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ByteData? raw = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    descriptor.dispose();
    codec.dispose();
    final Uint8List pixels = raw!.buffer.asUint8List();
    return (targetWidth, targetHeight, pixels);
  }

  /// RGBA → NV21（Android）：Y 平面 + 2×2 下采样的 VU 交织平面。
  static Uint8List _rgbaToNv21(Uint8List rgba, int width, int height) {
    final int ySize = width * height;
    final int chromaPairs = (width ~/ 2) * (height ~/ 2);
    final Uint8List nv21 = Uint8List(ySize + chromaPairs * 2);
    int yIndex = 0;
    for (int p = 0; p < ySize * 4; p += 4) {
      final int y = (rgba[p] * 77 + rgba[p + 1] * 151 + rgba[p + 2] * 28) >> 8;
      nv21[yIndex++] = y.clamp(0, 255);
    }
    int uvIndex = ySize;
    for (int row = 0; row < height; row += 2) {
      for (int col = 0; col < width; col += 2) {
        final int p = (row * width + col) * 4;
        final int r = rgba[p];
        final int g = rgba[p + 1];
        final int b = rgba[p + 2];
        final int v = ((r * 128 - g * 107 - b * 21) >> 8) + 128;
        final int u = ((b * 128 - r * 43 - g * 85) >> 8) + 128;
        nv21[uvIndex++] = v.clamp(0, 255);
        nv21[uvIndex++] = u.clamp(0, 255);
      }
    }
    return nv21;
  }

  /// RGBA → BGRA8888（iOS）：ML Kit 在 iOS 上只认这个内存格式。
  static Uint8List _rgbaToBgra(Uint8List rgba) {
    final Uint8List bgra = Uint8List(rgba.length);
    for (int p = 0; p < rgba.length; p += 4) {
      bgra[p] = rgba[p + 2];
      bgra[p + 1] = rgba[p + 1];
      bgra[p + 2] = rgba[p];
      bgra[p + 3] = rgba[p + 3];
    }
    return bgra;
  }

  /// 只留字母数字：OCR 偶尔会把噪点读成标点或空格。
  static String _alphanumeric(String raw) {
    final StringBuffer out = StringBuffer();
    for (final int unit in raw.codeUnits) {
      final String ch = String.fromCharCode(unit);
      if ((unit >= 0x30 && unit <= 0x39) ||
          (unit >= 0x41 && unit <= 0x5A) ||
          (unit >= 0x61 && unit <= 0x7A)) {
        out.write(ch);
      }
    }
    // 正常验证码 4 位；读出超过 6 位基本是把噪点/水印也认进来了，宁可信不过。
    final String text = out.toString();
    return text.length > 6 ? '' : text;
  }
}

CaptchaRecognizer createCaptchaRecognizer() => MlKitCaptchaRecognizer();
