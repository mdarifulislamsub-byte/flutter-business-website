library html;
import 'dart:typed_data';
class Blob {
  Blob(List<dynamic> blobs, String type);
}
class UrlClass {
  String createObjectUrlFromBlob(dynamic blob) => '';
  void revokeObjectUrl(String url) {}
}
final UrlClass Url = UrlClass();
class AnchorElement {
  String? href;
  AnchorElement({this.href});
  void setAttribute(String name, String value) {}
  void click() {}
}
class Window {
  void open(String url, String target) {}
}
final Window window = Window();
class FileUploadInputElement {
  String? accept;
  void click() {}
  Stream<dynamic> get onChange => const Stream.empty();
  List<dynamic>? get files => null;
}
class FileReader {
  void readAsArrayBuffer(dynamic blob) {}
  Stream<dynamic> get onLoadEnd => const Stream.empty();
  dynamic get result => null;
}