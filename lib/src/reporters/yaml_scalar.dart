import 'dart:convert';

/// Plain scalars that YAML would read as something other than a string.
const _reserved = {
  'true', 'false', 'null', 'yes', 'no', 'on', 'off', '~', //
  'True', 'False', 'Null', 'Yes', 'No', 'On', 'Off',
  'TRUE', 'FALSE', 'NULL', 'YES', 'NO', 'ON', 'OFF',
};

/// No spaces, so `: ` and ` #` cannot occur; a trailing `:` is excluded
/// separately. The first character is never a digit or `.`, so no number
/// (`.5`, `.inf`, `.nan`) reads as plain.
final _plain = RegExp(r'^[A-Za-z_/][A-Za-z0-9_/.@+:-]*$');

/// [value] as a YAML scalar that always reads back as the same string:
/// plain when unambiguous (paths, identifiers), otherwise double-quoted
/// (a JSON string is a valid YAML double-quoted scalar).
String yamlScalar(String value) =>
    _plain.hasMatch(value) && !value.endsWith(':') && !_reserved.contains(value)
    ? value
    : jsonEncode(value);
