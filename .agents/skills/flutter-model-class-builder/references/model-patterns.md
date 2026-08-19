# Model Patterns

## 单模型模板

```dart
class XxxModel {
  final int id;
  final String name;
  final List<String> images;

  const XxxModel({
    this.id = 0,
    this.name = '',
    this.images = const [],
  });

  bool get isEmpty => id == 0 && name.isEmpty && images.isEmpty;

  XxxModel copyWith({
    int? id,
    String? name,
    List<String>? images,
  }) {
    return XxxModel(
      id: id ?? this.id,
      name: name ?? this.name,
      images: images ?? this.images,
    );
  }

  factory XxxModel.fromMap(Map<String, dynamic> map) {
    return XxxModel(
      id: map.optInt('id'),
      name: map.optString('name'),
      images: map.optStringList('images'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'images': images,
    };
  }

  factory XxxModel.fromJson(Map<String, dynamic> json) => XxxModel.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is XxxModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          TypeUtil.equal(images, other.images));

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ images.hashCode;

  @override
  String toString() {
    return 'XxxModel${TypeUtil.parseString(toMap())}';
  }
}
```

## 默认值

- `int`: `0`
- `double`: `0.0`
- `String`: `''`
- `bool`: `false`
- `List<T>`: `const []`
- `Map<String, dynamic>`: `const {}`
- 嵌套模型：`const ChildModel()`，前提是子模型有 const 默认构造。
- 响应包装类如果必须表达“服务端必返”，可以用 `required this.items`，但普通业务模型优先默认值。

## 嵌套模型

- `fromMap`: `profile: ProfileModel.fromJson(map.optMap('profile'))`
- 可空基础字段使用 `map.optXxxOrNull('field')`；可空嵌套模型使用 `map.optMapOrNull('field')` 配合 null 判断。
- `toMap`: `'profile': profile.toMap()`
- `isEmpty`: `profile.isEmpty`，仅当子模型有 `isEmpty`。

## 列表模型

- 字符串列表：`map.optStringList('images')`
- 整型列表：`map.optIntList('ids')`
- 对象列表：`map.optMapList('items').map((e) => ItemModel.fromJson(e)).toList()`
- 回写对象列表：`'items': items.map((e) => e.toMap()).toList()`
- 等值比较：`TypeUtil.equal(items, other.items)`
