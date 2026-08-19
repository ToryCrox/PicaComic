# Spec Format

`scripts/generate_model.py` 接收 JSON spec。最小结构：

```json
{
  "classes": [
    {
      "className": "UserTag",
      "includeIsEmpty": false,
      "fields": [
        {
          "name": "id",
          "type": "int",
          "key": "id",
          "default": "0",
          "comment": "用户标签的ID"
        },
        {
          "name": "name",
          "type": "String",
          "key": "name",
          "default": "''",
          "comment": "标签所展示的文案"
        }
      ]
    }
  ]
}
```

也可以只传单个类：

```json
{
  "className": "UserTag",
  "fields": []
}
```

## class 字段

- `className`: 必填，Dart 类名。
- `fields`: 必填，字段数组。
- `includeIsEmpty`: 可选，默认 `true`。
- `emptyCheck`: 可选，自定义整段 `isEmpty` 表达式。

## field 字段

- `name`: 必填，Dart 字段名。
- `type`: 必填，Dart 类型，例如 `int`、`String`、`List<UserTag>`。
- `key`: 可选，服务端 key；默认等于 `name`。
- `default`: 可选，构造函数默认值；不填时脚本按类型推断。
- `required`: 可选，`true` 时构造参数使用 `required this.name`。
- `comment`: 可选，生成 `///` 注释。
- `fromMap`: 可选，自定义 fromMap 右侧表达式。
- `toMap`: 可选，自定义 toMap 右侧表达式。
- `emptyCheck`: 可选，自定义该字段的 `isEmpty` 判断表达式。
- `equality`: 可选，自定义该字段的等值比较表达式。

自定义表达式中可以直接引用 `map`、字段名和 `other`。

注意：脚本保持项目里常见的简单 `copyWith` 风格。可空字段的 `copyWith` 不能区分“未传参数”和“显式传 null”，如果业务需要清空字段，需要生成后人工改成 sentinel 写法或补充自定义方法。
