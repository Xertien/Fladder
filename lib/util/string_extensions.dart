import 'package:path/path.dart' as path;

import 'package:fladder/models/items/item_shared_models.dart';

extension StringExtensions on String {
  String get asciiHeaderSafe {
    const folded = {
      'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n', 'ý': 'y', 'ÿ': 'y', 'æ': 'ae', 'œ': 'oe', 'ß': 'ss',
    };
    final buffer = StringBuffer();
    for (final char in split('')) {
      final lower = char.toLowerCase();
      final match = folded[lower];
      if (match != null) {
        buffer.write(char == lower ? match : match.toUpperCase());
      } else if (char.codeUnitAt(0) >= 0x20 && char.codeUnitAt(0) <= 0x7E) {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  String capitalize() {
    if (isEmpty) return '';
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }

  String rtrim([String? chars]) {
    var pattern = chars != null ? RegExp('[$chars]+\$') : RegExp(r'\s+$');
    return replaceAll(pattern, '');
  }

  String maxLength({int limitTo = 75}) {
    if (isEmpty) return this;
    if (length > limitTo) {
      return "${substring(0, limitTo.clamp(0, length))}...";
    } else {
      return substring(0, limitTo.clamp(0, length));
    }
  }

  String getInitials({int limitTo = 2}) {
    if (isEmpty) return "";

    var split = trim().split(RegExp(r'\s+(?=[A-Z])|\s+|(?=[A-Z])'));

    var words = split.where((w) => w.isNotEmpty).toList();

    var buffer = StringBuffer();
    for (var i = 0; i < (limitTo.clamp(0, words.length)); i++) {
      buffer.write(words[i][0]);
    }

    return buffer.toString();
  }

  String toUpperCaseSplit({RegExp? regExp}) {
    String result = '';

    RegExp defaultRegex = regExp ?? RegExp(r'^[a-zA-Z]+$');

    for (int i = 0; i < length; i++) {
      if (i == 0) {
        result += this[i].toUpperCase();
      } else if ((i > 0 && this[i].toUpperCase() == this[i]) && defaultRegex.hasMatch(this[i]) == true) {
        result += ' ${this[i].toUpperCase()}';
      } else {
        result += this[i];
      }
    }

    return result;
  }

  String get sanitizedFileName {
    var name = path.basename(this).trim();

    name = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    name = name.replaceAll(RegExp(r'[\. ]+$'), '');

    if (name.isEmpty) name = 'file';

    if (name.length > 200) name = name.substring(0, 200);

    return name;
  }

  /// Supports both Linux and Windows server path separators as referenced in [path.separator].
  /// Instead of the [path.basename] method, which returns the last part of the path for the current client platform.
  String get universalBasename {
    final parts = split(RegExp(r'[\\/]+'));
    return parts.where((s) => s.isNotEmpty).lastOrNull ?? '';
  }
}

extension ListExtensions on List<String> {
  String flatString({int count = 3}) {
    return take(3).map((e) => e.capitalize()).join(" | ");
  }
}

extension GenreExtensions on List<GenreItems> {
  String flatString({int count = 3}) {
    return take(3).map((e) => e.name.capitalize()).join(" | ");
  }
}

extension StringListExtension on List<String?> {
  String get detailsTitle {
    return nonNulls.join(" ● ");
  }
}
