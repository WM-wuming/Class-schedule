# google_mlkit_text_recognition 只带了拉丁文识别模型（com.google.mlkit:text-recognition），
# 但它的 consumer proguard 规则会引用其它语言识别器（中文/日文/韩文/天城文）的类，
# 那些类在单独的 artifact 里，我们没打包 —— R8 报 Missing class。这里明确放行。
# 本应用只用拉丁文识别（验证码是字母数字），不需要那些模型。
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**

# 保险：真机上识别「永远失败」的一个嫌疑是 R8 把 ML Kit 运行时需要的类
# 裁坏/重命名了（consumer rules 覆盖不到我们自定义的调用方式）。
# ML Kit 本体保留不裁，APK 体积代价可接受（模型本来就在里面）。
-keep class com.google.mlkit.** { *; }
