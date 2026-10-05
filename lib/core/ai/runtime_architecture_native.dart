import 'dart:ffi';

bool get supportsBundledAiArchitecture => const {
  Abi.androidArm64,
  Abi.iosArm64,
  Abi.macosArm64,
  Abi.linuxX64,
  Abi.linuxArm64,
  Abi.windowsX64,
}.contains(Abi.current());
