package com.saoshu.xindian;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

final class TiebaProto {
    private TiebaProto() {
    }

    static final class Field {
        final long number;
        final int wireType;
        final long varint;
        final byte[] bytes;

        Field(long number, int wireType, long varint, byte[] bytes) {
            this.number = number;
            this.wireType = wireType;
            this.varint = varint;
            this.bytes = bytes;
        }
    }

    static final class Message {
        private final Map<Long, List<Field>> fields = new LinkedHashMap<>();

        static Message parse(byte[] data) {
            Message message = new Message();
            int cursor = 0;
            while (cursor < data.length) {
                Varint tag = readVarint(data, cursor);
                cursor = tag.next;
                long number = tag.value >>> 3;
                int wireType = (int) (tag.value & 7);
                if (number <= 0) {
                    throw new IllegalArgumentException("Invalid protobuf field number");
                }
                Field field;
                if (wireType == 0) {
                    Varint value = readVarint(data, cursor);
                    cursor = value.next;
                    field = new Field(number, wireType, value.value, null);
                } else if (wireType == 1) {
                    if (cursor + 8 > data.length) {
                        throw new IllegalArgumentException("Truncated protobuf fixed64");
                    }
                    field = new Field(number, wireType, 0,
                            slice(data, cursor, cursor + 8));
                    cursor += 8;
                } else if (wireType == 2) {
                    Varint length = readVarint(data, cursor);
                    cursor = length.next;
                    long endLong = cursor + length.value;
                    if (length.value < 0 || endLong > data.length) {
                        throw new IllegalArgumentException("Truncated protobuf bytes");
                    }
                    int end = (int) endLong;
                    field = new Field(number, wireType, 0,
                            slice(data, cursor, end));
                    cursor = end;
                } else if (wireType == 5) {
                    if (cursor + 4 > data.length) {
                        throw new IllegalArgumentException("Truncated protobuf fixed32");
                    }
                    field = new Field(number, wireType, 0,
                            slice(data, cursor, cursor + 4));
                    cursor += 4;
                } else {
                    throw new IllegalArgumentException(
                            "Unsupported protobuf wire type " + wireType);
                }
                List<Field> values = message.fields.get(number);
                if (values == null) {
                    values = new ArrayList<>();
                    message.fields.put(number, values);
                }
                values.add(field);
            }
            return message;
        }

        boolean has(long number) {
            List<Field> values = fields.get(number);
            return values != null && !values.isEmpty();
        }

        long varint(long number, long fallback) {
            Field field = first(number);
            return field == null ? fallback : field.varint;
        }

        String text(long number) {
            Field field = first(number);
            return field == null || field.bytes == null
                    ? "" : new String(field.bytes, StandardCharsets.UTF_8);
        }

        byte[] bytes(long number) {
            Field field = first(number);
            return field == null || field.bytes == null ? null : field.bytes;
        }

        Message message(long number) {
            byte[] value = bytes(number);
            return value == null ? null : parse(value);
        }

        List<Field> repeated(long number) {
            List<Field> result = fields.get(number);
            return result == null ? Collections.emptyList()
                    : Collections.unmodifiableList(result);
        }

        List<Message> messages(long number) {
            List<Field> raw = fields.get(number);
            if (raw == null || raw.isEmpty()) {
                return Collections.emptyList();
            }
            List<Message> result = new ArrayList<>(raw.size());
            for (Field field : raw) {
                if (field.wireType == 2 && field.bytes != null) {
                    result.add(parse(field.bytes));
                }
            }
            return result;
        }

        private Field first(long number) {
            List<Field> values = fields.get(number);
            return values == null || values.isEmpty() ? null : values.get(0);
        }
    }

    static final class Writer {
        private final ByteArrayOutputStream output = new ByteArrayOutputStream();

        Writer varint(int tag, long value) {
            writeRawVarint(tag, 0);
            writeRawVarint(value);
            return this;
        }

        Writer text(int tag, String value) {
            byte[] data = (value == null ? "" : value)
                    .getBytes(StandardCharsets.UTF_8);
            writeRawVarint(tag, 2);
            writeRawVarint(data.length);
            output.write(data, 0, data.length);
            return this;
        }

        Writer message(int tag, Writer value) {
            return message(tag, value.bytes());
        }

        Writer message(int tag, byte[] value) {
            writeRawVarint(tag, 2);
            writeRawVarint(value.length);
            output.write(value, 0, value.length);
            return this;
        }

        byte[] bytes() {
            return output.toByteArray();
        }

        private void writeRawVarint(int tag, int wireType) {
            writeRawVarint(((long) tag << 3) | wireType);
        }

        private void writeRawVarint(long value) {
            while (true) {
                int part = (int) (value & 0x7f);
                value >>>= 7;
                if (value == 0) {
                    output.write(part);
                    return;
                }
                output.write(part | 0x80);
            }
        }
    }

    private static final class Varint {
        final long value;
        final int next;

        Varint(long value, int next) {
            this.value = value;
            this.next = next;
        }
    }

    private static Varint readVarint(byte[] data, int start) {
        long value = 0;
        int shift = 0;
        int cursor = start;
        while (cursor < data.length && shift <= 63) {
            int part = data[cursor++] & 0xff;
            value |= (long) (part & 0x7f) << shift;
            if ((part & 0x80) == 0) {
                return new Varint(value, cursor);
            }
            shift += 7;
        }
        throw new IllegalArgumentException("Invalid protobuf varint");
    }

    private static byte[] slice(byte[] data, int start, int end) {
        byte[] result = new byte[end - start];
        System.arraycopy(data, start, result, 0, result.length);
        return result;
    }
}
