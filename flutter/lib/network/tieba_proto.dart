import 'dart:convert';
import 'dart:typed_data';

/// 贴吧 protobuf 极简读写（Dart 版，逐行移植自原生 TiebaProto.java）。
class PbField {
  final int number;
  final int wireType;
  final int varintValue;
  final Uint8List? bytesValue;
  const PbField(this.number, this.wireType, this.varintValue, this.bytesValue);
}

class PbMessage {
  final Map<int, List<PbField>> _fields = {};

  static PbMessage parse(Uint8List data) {
    final message = PbMessage();
    var cursor = 0;
    while (cursor < data.length) {
      final tag = _readVarint(data, cursor);
      cursor = tag.next;
      final number = tag.value >>> 3;
      final wireType = tag.value & 7;
      if (number <= 0) {
        throw const FormatException('Invalid protobuf field number');
      }
      PbField field;
      if (wireType == 0) {
        final value = _readVarint(data, cursor);
        cursor = value.next;
        field = PbField(number, wireType, value.value, null);
      } else if (wireType == 1) {
        field = PbField(number, wireType, 0, _slice(data, cursor, cursor + 8));
        cursor += 8;
      } else if (wireType == 2) {
        final length = _readVarint(data, cursor);
        cursor = length.next;
        final end = cursor + length.value;
        if (end > data.length) {
          throw const FormatException('Truncated protobuf bytes');
        }
        field = PbField(number, wireType, 0, _slice(data, cursor, end));
        cursor = end;
      } else if (wireType == 5) {
        field = PbField(number, wireType, 0, _slice(data, cursor, cursor + 4));
        cursor += 4;
      } else {
        throw FormatException('Unsupported wire type $wireType');
      }
      message._fields.putIfAbsent(number, () => []).add(field);
    }
    return message;
  }

  bool has(int number) => _fields[number]?.isNotEmpty ?? false;

  int varint(int number, [int fallback = 0]) {
    final field = _first(number);
    return field == null ? fallback : field.varintValue;
  }

  String text(int number) {
    final field = _first(number);
    if (field?.bytesValue == null) return '';
    return utf8.decode(field!.bytesValue!);
  }

  Uint8List? bytes(int number) => _first(number)?.bytesValue;

  PbMessage? message(int number) {
    final value = bytes(number);
    return value == null ? null : parse(value);
  }

  List<PbMessage> messages(int number) {
    final raw = _fields[number];
    if (raw == null) return const [];
    return raw
        .where((f) => f.wireType == 2 && f.bytesValue != null)
        .map((f) => parse(f.bytesValue!))
        .toList();
  }

  PbField? _first(int number) {
    final values = _fields[number];
    return (values == null || values.isEmpty) ? null : values.first;
  }
}

class PbWriter {
  final BytesBuilder _output = BytesBuilder(copy: false);

  void varintField(int tag, int value) {
    _writeRawVarint((tag << 3) | 0);
    _writeRawVarint(value);
  }

  void textField(int tag, String value) {
    final data = utf8.encode(value);
    _writeRawVarint((tag << 3) | 2);
    _writeRawVarint(data.length);
    _output.add(data);
  }

  void bytesField(int tag, Uint8List value) {
    _writeRawVarint((tag << 3) | 2);
    _writeRawVarint(value.length);
    _output.add(value);
  }

  void messageField(int tag, PbWriter value) => bytesField(tag, value.toBytes());

  Uint8List toBytes() => _output.toBytes();

  void _writeRawVarint(int value) {
    while (true) {
      final part = value & 0x7f;
      value >>>= 7;
      if (value == 0) {
        _output.addByte(part);
        return;
      }
      _output.addByte(part | 0x80);
    }
  }
}

class _Varint {
  final int value;
  final int next;
  const _Varint(this.value, this.next);
}

_Varint _readVarint(Uint8List data, int start) {
  var value = 0;
  var shift = 0;
  var cursor = start;
  while (cursor < data.length && shift <= 63) {
    final part = data[cursor++];
    value |= (part & 0x7f) << shift;
    if ((part & 0x80) == 0) {
      return _Varint(value, cursor);
    }
    shift += 7;
  }
  throw const FormatException('Invalid protobuf varint');
}

Uint8List _slice(Uint8List data, int start, int end) =>
    Uint8List.sublistView(data, start, end);
