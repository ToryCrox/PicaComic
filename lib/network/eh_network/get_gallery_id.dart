///从画廊链接中获取画廊id
String getGalleryId(String url) {
  var i = url.indexOf("/g/");
  if (i == -1) {
    // 假设如果不是链接本身，可能传入的就是纯数字id
    return url;
  }
  i += 3;
  String res = "";
  while (i < url.length && url[i] != '/') {
    res += url[i];
    i++;
  }
  return res;
}
