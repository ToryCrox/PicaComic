import 'package:rhttp/rhttp.dart';

/// 初始化 rhttp 的 Rust 运行时。
Future<void> initializeRhttp() => Rhttp.init();
