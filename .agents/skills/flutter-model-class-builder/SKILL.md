---
name: flutter-model-class-builder
description: 按手写 Dart Model 风格生成 Flutter 数据模型类，包含 final 字段、const 默认构造、copyWith、fromMap/toMap、fromJson/toJson、等值比较与 hashCode。用于用户要求“根据字段定义创建模型类”、“将接口 JSON 转为 Dart Model”、“按 UserInfoModel 类似风格手写模型”时。
---

# Flutter Model Class Builder

生成 Flutter 手写 Model 时使用本 skill。核心原则：模型负责理解接口与业务语义，脚本负责生成重复且容易漏字段的代码。

## 1. 判断输入

先收集或推断：
- 类名
- 字段名与 Dart 类型
- 服务端 key（通常是 `snake_case`）
- 嵌套对象与对象数组
- 是否需要 `isEmpty`、业务派生 getter、响应包装类

缺失信息时，优先做可落地的默认假设，并在回复中标注。

## 2. 优先脚本生成

字段较多、需要多个模型、或用户要求稳定输出时，优先创建临时 JSON spec，然后运行：

```bash
python3 .agents/skills/flutter-model-class-builder/scripts/generate_model.py --spec /path/to/spec.json --stdout
```

spec 写法见 [references/spec-format.md](references/spec-format.md)。脚本会稳定生成：
- `final` 字段
- `const` 构造函数
- `isEmpty`（按 spec 开关）
- `copyWith(...)`
- `factory fromMap(Map<String, dynamic> map)`
- `Map<String, dynamic> toMap()`
- `fromJson/toJson`
- `operator ==` 与 `hashCode`
- `toString()`

生成后必须人工检查：类型推断、服务端 key、嵌套模型名、import、业务 getter、字段默认值是否符合当前文件上下文。

## 3. 风格规则

- 本地字段用 `lowerCamelCase`，服务端 key 保留接口命名。
- `fromMap/fromJson` 从 Map 读取字段时优先使用 `map.optXxx(...)` 或 `map.optXxxOrNull(...)`；禁止直接使用 `as` 强转读取接口字段。
- 基础类型：`int`/`String`/`bool`/`double` 优先使用对应 `map.optInt`/`optString`/`optBool`/`optDouble`；可空字段使用 `optIntOrNull` 等可空版本。
- `List<String>`/`List<int>` 优先使用 `map.optStringList`/`map.optIntList`；没有对应扩展或需要逐项转换时使用 `map.optList`，回调内部再使用 `TypeUtil.parseXxx`。
- 对象列表优先使用 `map.optMapList('items').map((e) => ItemModel.fromJson(e)).toList()`，避免在回调中重复 `TypeUtil.parseMap`。
- 嵌套对象使用 `ChildModel.fromJson(map.optMap('child'))`；可空嵌套对象使用 `optMapOrNull` 配合必要的 null 判断；回写使用 `child.toMap()`。
- `TypeUtil.parseXxx` 作为底层转换工具，适用于原始动态值、非 Map 场景、集合转换回调和没有对应 `optXxx` 扩展的类型。
- 列表、Map 等集合字段在 `operator ==` 中使用 `TypeUtil.equal(...)`。
- 默认保持纯 Dart 手写模型，不引入代码生成和不必要依赖，不输出 `.g.dart` 风格代码。
- 除非用户要求，否则不混入业务逻辑，只保留轻量派生属性。

更多模板和边界情况见 [references/model-patterns.md](references/model-patterns.md)。

## 4. 修改文件约束

- 修改已有 Dart 文件时不要整体格式化代码。
- 新添加的 Dart 文件可以格式化代码。
- 如果只是给用户输出代码片段，输出完整、可直接粘贴的 Dart 代码。
- 多个模型按“主模型 -> 子模型 -> 响应包装模型”的顺序输出。
