// TODO(nikeokoronkwo): Make platform-agnostic
import 'dart:io';
import 'dart:typed_data';

import '../format.dart';

class GzipCompressionFormat extends CompressionFormat {
  const GzipCompressionFormat();

  @override
  String get contentType => "application/gzip";

  @override
  Uint8List convert(Uint8List data) {
    return Uint8List.fromList(gzip.decode(data));
  }

  @override
  String get extension => "gz";

  @override
  String? get contentEncoding => "gzip";

  @override
  List<int>? get magicBytes => [0x1F, 0x8B];
}
