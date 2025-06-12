import 'dart:math';

extension StringExt on String {

  int compareIndex(String str) {
    final name1 = this;
    final name2 = str;
    final minLen = min(name1.length, name2.length);
    var k = 0;

    while (k < minLen) {
      final c1 = name1[k];
      final c2 = name2[k];

      final i1 = int.tryParse(c1);
      final i2 = int.tryParse(c2);
      if (i1 != null && i2 != null) {
        final p1 = name1.subDigitNum(c1, k);
        final p2 = name2.subDigitNum(c2, k);
        final rs = p1.index - p2.index;
        return rs != 0 ? rs : p1.str.compareIndex(p2.str);
      } else if (c1 != c2) {
        return c1.compareTo(c2);
      }
      k++;
    }
    return name1.compareTo(name2);
  }

  IntPair subDigitNum(String c1, int start) {
    final sb1 = StringBuffer();
    final sb2 = StringBuffer();
    sb1.write(c1);
    var isInStr = false;
    for (var i = start + 1; i < length; i++) {
      final c = this[i];
      final ci = int.tryParse(c);
      if (ci != null && !isInStr) {
        sb1.write(c);
      } else {
        isInStr = true;
        sb2.write(c);
      }
    }
    return IntPair(int.parse(sb1.toString()), sb2.toString());
  }
}

class IntPair {
  final int index;
  final String str;

  const IntPair(this.index, this.str);
}