#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path


PRIMITIVE_PARSERS = {
    "int": "TypeUtil.parseInt",
    "String": "TypeUtil.parseString",
    "bool": "TypeUtil.parseBool",
    "double": "TypeUtil.parseDouble",
    "Color": "TypeUtil.parseColor",
}

MAP_PRIMITIVE_PARSERS = {
    "int": "optInt",
    "String": "optString",
    "bool": "optBool",
    "double": "optDouble",
}

LIST_PARSERS = {
    "String": "TypeUtil.parseStringList",
    "int": "TypeUtil.parseIntList",
    "Map<String, dynamic>": "TypeUtil.parseMapList",
}

MAP_LIST_PARSERS = {
    "String": "optStringList",
    "int": "optIntList",
    "Map<String, dynamic>": "optMapList",
}


def main():
    parser = argparse.ArgumentParser(description="Generate hand-written Dart model classes.")
    parser.add_argument("--spec", required=True, help="Path to a JSON spec file.")
    parser.add_argument("--stdout", action="store_true", help="Print generated Dart to stdout.")
    parser.add_argument("--output", help="Path to write generated Dart.")
    args = parser.parse_args()

    spec = json.loads(Path(args.spec).read_text(encoding="utf-8"))
    classes = spec.get("classes") or [spec]
    code = "\n\n".join(generate_class(item) for item in classes)
    code += "\n"

    if args.output:
        Path(args.output).write_text(code, encoding="utf-8")
    if args.stdout or not args.output:
        sys.stdout.write(code)


def generate_class(spec):
    class_name = require(spec, "className")
    fields = spec.get("fields") or []
    if not fields:
        raise ValueError(f"{class_name}: fields must not be empty")

    include_is_empty = spec.get("includeIsEmpty", True)
    lines = [f"class {class_name} {{"]
    lines.extend(field_declarations(fields))
    lines.append("")
    lines.extend(constructor(class_name, fields))
    if include_is_empty:
        lines.append("")
        lines.extend(is_empty_getter(fields, spec.get("emptyCheck")))
    lines.append("")
    lines.extend(copy_with(class_name, fields))
    lines.append("")
    lines.extend(from_map(class_name, fields))
    lines.append("")
    lines.extend(to_map(fields))
    lines.append("")
    lines.extend(json_methods(class_name))
    lines.append("")
    lines.extend(equals(class_name, fields))
    lines.append("")
    lines.extend(hash_code(fields))
    lines.append("")
    lines.extend(to_string(class_name))
    lines.append("}")
    return "\n".join(lines)


def field_declarations(fields):
    lines = []
    for field in fields:
        comment = field.get("comment")
        if comment:
            for line in str(comment).splitlines():
                lines.append(f"  /// {line}")
        lines.append(f"  final {require(field, 'type')} {require(field, 'name')};")
        lines.append("")
    if lines:
        lines.pop()
    return lines


def constructor(class_name, fields):
    lines = [f"  const {class_name}({{"]
    for field in fields:
        name = require(field, "name")
        if field.get("required"):
            lines.append(f"    required this.{name},")
        elif "default" not in field and require(field, "type").endswith("?"):
            lines.append(f"    this.{name},")
        else:
            lines.append(f"    this.{name} = {default_value(field)},")
    lines.append("  });")
    return lines


def is_empty_getter(fields, custom_expression):
    expression = custom_expression or " &&\n".join(empty_check(field) for field in fields)
    return wrap_expression("  bool get isEmpty =>", expression)


def copy_with(class_name, fields):
    lines = [f"  {class_name} copyWith({{"]
    for field in fields:
        lines.append(f"    {nullable_type(require(field, 'type'))} {require(field, 'name')},")
    lines.append("  }) {")
    lines.append(f"    return {class_name}(")
    for field in fields:
        name = require(field, "name")
        lines.append(f"      {name}: {name} ?? this.{name},")
    lines.append("    );")
    lines.append("  }")
    return lines


def from_map(class_name, fields):
    lines = [f"  factory {class_name}.fromMap(Map<String, dynamic> map) {{", f"    return {class_name}("]
    for field in fields:
        lines.append(f"      {require(field, 'name')}: {from_map_value(field)},")
    lines.append("    );")
    lines.append("  }")
    return lines


def to_map(fields):
    lines = ["  Map<String, dynamic> toMap() {", "    return {"]
    for field in fields:
        key = field.get("key", require(field, "name"))
        lines.append(f"      '{key}': {to_map_value(field)},")
    lines.append("    };")
    lines.append("  }")
    return lines


def json_methods(class_name):
    return [
        f"  factory {class_name}.fromJson(Map<String, dynamic> json) =>",
        f"      {class_name}.fromMap(json);",
        "",
        "  Map<String, dynamic> toJson() => toMap();",
    ]


def equals(class_name, fields):
    comparisons = []
    for field in fields:
        name = require(field, "name")
        comparisons.append(field.get("equality") or default_equality(name, require(field, "type")))
    comparison_expression = " &&\n    ".join(comparisons)
    expression = (
        "identical(this, other) ||\n"
        f"(other is {class_name} &&\n"
        "    runtimeType == other.runtimeType &&\n"
        f"    {comparison_expression})"
    )
    lines = ["  @override"]
    lines.extend(wrap_expression("  bool operator ==(Object other) =>", expression))
    return lines


def hash_code(fields):
    expression = " ^\n".join(f"{require(field, 'name')}.hashCode" for field in fields)
    lines = ["  @override"]
    lines.extend(wrap_expression("  int get hashCode =>", expression))
    return lines


def to_string(class_name):
    return [
        "  @override",
        "  String toString() {",
        f"    return '{class_name}${{TypeUtil.parseString(toMap())}}';",
        "  }",
    ]


def from_map_value(field):
    if field.get("fromMap"):
        return field["fromMap"]

    dart_type = require(field, "type")
    key = field.get("key", require(field, "name"))
    access = f"map['{key}']"
    nullable = dart_type.endswith("?")
    base_type = strip_nullable(dart_type)

    if nullable:
        return nullable_from_map_value(base_type, key, access)
    if base_type in MAP_PRIMITIVE_PARSERS:
        return f"map.{MAP_PRIMITIVE_PARSERS[base_type]}('{key}')"
    if base_type in PRIMITIVE_PARSERS:
        return f"{PRIMITIVE_PARSERS[base_type]}({access})"
    if base_type == "Map<String, dynamic>":
        return f"map.optMap('{key}')"

    list_item = list_item_type(base_type)
    if list_item:
        return list_from_map_value(list_item, key, access)

    if is_model_type(base_type):
        return f"{base_type}.fromJson(map.optMap('{key}'))"
    return access


def nullable_from_map_value(base_type, key, access):
    if base_type in MAP_PRIMITIVE_PARSERS:
        return f"map.{MAP_PRIMITIVE_PARSERS[base_type]}OrNull('{key}')"
    if base_type in PRIMITIVE_PARSERS:
        return f"{access} == null ? null : {PRIMITIVE_PARSERS[base_type]}({access})"
    if base_type == "Map<String, dynamic>":
        return f"map.optMapOrNull('{key}')"
    item_type = list_item_type(base_type)
    if item_type:
        return f"{access} == null ? null : {list_from_map_value(item_type, key, access)}"
    if is_model_type(base_type):
        return f"map.optMapOrNull('{key}') == null ? null : {base_type}.fromJson(map.optMap('{key}'))"
    return access


def list_from_map_value(item_type, key, access):
    if item_type in MAP_LIST_PARSERS:
        return f"map.{MAP_LIST_PARSERS[item_type]}('{key}')"
    if item_type in LIST_PARSERS:
        return f"{LIST_PARSERS[item_type]}({access})"
    if item_type == "double":
        return f"map.optList('{key}', (e) => TypeUtil.parseDouble(e))"
    if item_type == "bool":
        return f"map.optList('{key}', (e) => TypeUtil.parseBool(e))"
    if item_type == "Color":
        return f"map.optList('{key}', (e) => TypeUtil.parseColor(e))"
    if is_model_type(item_type):
        return f"map.optMapList('{key}').map((e) => {item_type}.fromJson(e)).toList()"
    return f"map.optList('{key}', (e) => e)"


def to_map_value(field):
    if field.get("toMap"):
        return field["toMap"]

    name = require(field, "name")
    raw_type = require(field, "type")
    nullable = raw_type.endswith("?")
    dart_type = strip_nullable(raw_type)
    item_type = list_item_type(dart_type)
    if item_type and is_model_type(item_type):
        if nullable:
            return f"{name}?.map((e) => e.toMap()).toList()"
        return f"{name}.map((e) => e.toMap()).toList()"
    if is_model_type(dart_type):
        if nullable:
            return f"{name}?.toMap()"
        return f"{name}.toMap()"
    return name


def default_equality(name, dart_type):
    base_type = strip_nullable(dart_type)
    if list_item_type(base_type) or base_type.startswith("Map<") or base_type in {"Map", "Set"}:
        return f"TypeUtil.equal({name}, other.{name})"
    return f"{name} == other.{name}"


def empty_check(field):
    if field.get("emptyCheck"):
        return field["emptyCheck"]

    name = require(field, "name")
    raw_type = require(field, "type")
    nullable = raw_type.endswith("?")
    dart_type = strip_nullable(raw_type)
    if nullable and is_model_type(dart_type):
        return f"({name}?.isEmpty ?? true)"
    if nullable:
        return f"TypeUtil.isEmpty({name})"
    if dart_type == "int":
        return f"{name} == 0"
    if dart_type == "double":
        return f"{name} == 0.0"
    if dart_type == "String":
        return f"{name}.isEmpty"
    if dart_type == "bool":
        return f"{name} == false"
    if list_item_type(dart_type) or dart_type.startswith("Map<"):
        return f"{name}.isEmpty"
    if is_model_type(dart_type):
        return f"{name}.isEmpty"
    return f"TypeUtil.isEmpty({name})"


def default_value(field):
    if "default" in field:
        return field["default"]

    dart_type = require(field, "type")
    if dart_type.endswith("?"):
        return "null"

    if dart_type == "int":
        return "0"
    if dart_type == "double":
        return "0.0"
    if dart_type == "String":
        return "''"
    if dart_type == "bool":
        return "false"
    if dart_type == "Color":
        return "Colors.transparent"
    if list_item_type(dart_type):
        return "const []"
    if dart_type.startswith("Map<"):
        return "const {}"
    if is_model_type(dart_type):
        return f"const {dart_type}()"
    return "null"


def nullable_type(dart_type):
    return dart_type if dart_type.endswith("?") else f"{dart_type}?"


def strip_nullable(dart_type):
    return dart_type[:-1] if dart_type.endswith("?") else dart_type


def list_item_type(dart_type):
    match = re.fullmatch(r"List<(.+)>", dart_type.strip())
    return match.group(1).strip() if match else None


def is_model_type(dart_type):
    if dart_type in PRIMITIVE_PARSERS:
        return False
    return bool(re.fullmatch(r"[A-Z]\w*", dart_type))


def wrap_expression(prefix, expression):
    parts = expression.splitlines()
    if len(parts) == 1 and len(prefix) + 1 + len(expression) <= 100:
        return [f"{prefix} {expression};"]
    lines = [prefix]
    lines.extend(f"      {part}" if part else part for part in parts)
    lines[-1] = f"{lines[-1]};"
    return lines


def require(data, key):
    value = data.get(key)
    if value is None or value == "":
        raise ValueError(f"Missing required key: {key}")
    return value


if __name__ == "__main__":
    main()
