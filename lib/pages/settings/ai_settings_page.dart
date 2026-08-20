import 'package:flutter/material.dart';
import 'package:pica_comic/ai/ai.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/tools/translations.dart';

/// AI 服务与提示词配置页面。
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: aiSettings,
    builder: (context, _) {
      if (!aiSettings.initialized) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        appBar: AppBar(
          title: Text('AI设置'.tl),
          bottom: TabBar(
            controller: _tabs,
            tabs: [
              Tab(text: '服务配置'.tl),
              Tab(text: '提示词'.tl),
            ],
          ),
        ),
        floatingActionButton: AnimatedBuilder(
          animation: _tabs,
          builder: (context, _) => FloatingActionButton.extended(
            onPressed: _tabs.index == 0 ? _editProvider : _editPrompt,
            icon: const Icon(Icons.add),
            label: Text(_tabs.index == 0 ? '添加服务'.tl : '添加提示词'.tl),
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [_buildProviders(), _buildPrompts()],
        ),
      );
    },
  );

  Widget _buildProviders() {
    final providers = aiSettings.providers;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'API Key将以明文保存在本机应用偏好设置中，请仅在可信设备上使用。'.tl,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        if (providers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '还没有AI服务配置。添加OpenAI或兼容服务后，即可绑定默认提示词。'.tl,
              textAlign: TextAlign.center,
            ),
          ),
        for (final provider in providers)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: ListTile(
              title: Text(provider.name),
              subtitle: Text(
                '${provider.protocol.label}\n${provider.model} · ${provider.baseUrl}',
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                position: PopupMenuPosition.under,
                onSelected: (value) => _handleProviderAction(value, provider),
                itemBuilder: (_) => [
                  popupMenuItem<String>(
                    value: 'test',
                    text: '测试连接'.tl,
                    icon: Icons.network_check,
                  ),
                  popupMenuItem<String>(
                    value: 'copy',
                    text: '复制'.tl,
                    icon: Icons.content_copy,
                  ),
                  popupMenuItem<String>(
                    value: 'edit',
                    text: '编辑'.tl,
                    icon: Icons.edit_outlined,
                  ),
                  popupMenuItem<String>(
                    value: 'delete',
                    text: '删除'.tl,
                    icon: Icons.delete_outline,
                  ),
                ],
              ),
              onTap: () => _editProvider(provider),
            ),
          ),
      ],
    );
  }

  Widget _buildPrompts() => ListView(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Expanded(child: Text('每个场景同时只会使用一条已启用提示词。'.tl)),
            TextButton(
              onPressed: aiSettings.restoreDefaultPrompts,
              child: Text('恢复默认'.tl),
            ),
          ],
        ),
      ),
      for (final prompt in aiSettings.prompts)
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: ListTile(
            leading: Radio<String>(
              value: prompt.id,
              groupValue: aiSettings.activePrompt(prompt.sceneId)?.id,
              onChanged: (_) => aiSettings.setPromptActive(prompt.id),
            ),
            title: Text(prompt.name),
            subtitle: Text(
              '${AiPromptScenes.labels[prompt.sceneId] ?? prompt.sceneId} · '
              '${aiSettings.providerById(prompt.providerId)?.name ?? '未绑定服务'.tl}',
            ),
            trailing: PopupMenuButton<String>(
              position: PopupMenuPosition.under,
              onSelected: (value) => _handlePromptAction(value, prompt),
              itemBuilder: (_) => [
                popupMenuItem<String>(
                  value: 'copy',
                  text: '复制'.tl,
                  icon: Icons.content_copy,
                ),
                popupMenuItem<String>(
                  value: 'edit',
                  text: '编辑'.tl,
                  icon: Icons.edit_outlined,
                ),
                popupMenuItem<String>(
                  value: 'delete',
                  text: '删除'.tl,
                  icon: Icons.delete_outline,
                ),
              ],
            ),
            onTap: () => _editPrompt(prompt),
          ),
        ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: OutlinedButton.icon(
          onPressed: _clearCache,
          icon: const Icon(Icons.delete_outline),
          label: Text('清空漫画翻译缓存'.tl),
        ),
      ),
    ],
  );

  Future<void> _handleProviderAction(
    String action,
    AiProviderConfig provider,
  ) async {
    switch (action) {
      case 'test':
        await _testProvider(provider);
        break;
      case 'copy':
        await _editProvider(
          provider.copyWith(
            id: aiSettings.newId('provider'),
            name: '${provider.name} ${'副本'.tl}',
          ),
        );
        break;
      case 'edit':
        await _editProvider(provider);
        break;
      case 'delete':
        try {
          await aiSettings.deleteProvider(provider.id);
        } catch (error) {
          _showError(error);
        }
        break;
    }
  }

  Future<void> _handlePromptAction(String action, AiPromptPreset prompt) async {
    switch (action) {
      case 'copy':
        await _editPrompt(
          prompt.copyWith(
            id: aiSettings.newId('prompt'),
            name: '${prompt.name} ${'副本'.tl}',
            isActive: false,
          ),
        );
        break;
      case 'edit':
        await _editPrompt(prompt);
        break;
      case 'delete':
        await aiSettings.deletePrompt(prompt.id);
        break;
    }
  }

  Future<void> _editProvider([AiProviderConfig? source]) async {
    final result = await showDialog<AiProviderConfig>(
      context: context,
      builder: (_) => _ProviderEditorDialog(
        provider:
            source ??
            AiProviderConfig(
              id: aiSettings.newId('provider'),
              name: '',
              protocol: AiProtocolType.openAiChatCompletions,
              baseUrl: 'https://api.openai.com/v1',
              apiKey: '',
              model: '',
            ),
      ),
    );
    if (result == null) return;
    try {
      await aiSettings.upsertProvider(result);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _editPrompt([AiPromptPreset? source]) async {
    final result = await showDialog<AiPromptPreset>(
      context: context,
      builder: (_) => _PromptEditorDialog(
        prompt:
            source ??
            AiPromptPreset(
              id: aiSettings.newId('prompt'),
              name: '',
              sceneId: AiPromptScenes.comicMetadataTranslation,
              providerId: aiSettings.providers.isEmpty
                  ? ''
                  : aiSettings.providers.first.id,
              systemPrompt: AiDefaultPrompts.comicMetadata.systemPrompt,
              userTemplate: AiDefaultPrompts.comicMetadata.userTemplate,
              isActive: false,
            ),
      ),
    );
    if (result == null) return;
    try {
      await aiSettings.upsertPrompt(result);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _testProvider(AiProviderConfig provider) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('正在测试AI服务连接…'.tl)));
    try {
      await aiClient.testConfig(provider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('连接成功'.tl)));
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _clearCache() async {
    await aiTranslationService.clearComicCache();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('漫画翻译缓存已清空'.tl)));
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }
}

class _ProviderEditorDialog extends StatefulWidget {
  final AiProviderConfig provider;
  const _ProviderEditorDialog({required this.provider});

  @override
  State<_ProviderEditorDialog> createState() => _ProviderEditorDialogState();
}

class _ProviderEditorDialogState extends State<_ProviderEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late AiProtocolType _protocol;
  String? _reasoningEffort;
  late int _maxRetries;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.provider.name);
    _baseUrl = TextEditingController(text: widget.provider.baseUrl);
    _apiKey = TextEditingController(text: widget.provider.apiKey);
    _model = TextEditingController(text: widget.provider.model);
    _protocol = widget.provider.protocol;
    _reasoningEffort = widget.provider.reasoningEffort;
    _maxRetries = widget.provider.maxRetries;
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.provider.name.isEmpty ? '添加AI服务'.tl : '编辑AI服务'.tl),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_name, '名称'.tl),
            DropdownButtonFormField<AiProtocolType>(
              value: _protocol,
              decoration: InputDecoration(labelText: '协议'.tl),
              items: AiProtocolType.values
                  .map(
                    (item) =>
                        DropdownMenuItem(value: item, child: Text(item.label)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _protocol = value!),
            ),
            _field(_baseUrl, 'Base URL', hint: 'https://api.openai.com/v1'),
            _field(
              _apiKey,
              'API Key（可留空）'.tl,
              obscureText: _obscureKey,
              suffix: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
            _field(_model, '模型'.tl, hint: 'gpt-4o-mini'),
            DropdownButtonFormField<String?>(
              value: _reasoningEffort,
              decoration: InputDecoration(labelText: '思考强度'.tl),
              items: [
                DropdownMenuItem(value: null, child: Text('默认（不发送）'.tl)),
                ...[
                  'none',
                  'minimal',
                  'low',
                  'medium',
                  'high',
                  'xhigh',
                  'max',
                ].map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                ),
              ],
              onChanged: (value) => setState(() => _reasoningEffort = value),
            ),
            DropdownButtonFormField<int>(
              initialValue: _maxRetries,
              decoration: InputDecoration(labelText: '失败重试次数'.tl),
              items: [
                for (var count = 0; count <= 10; count++)
                  DropdownMenuItem(
                    value: count,
                    child: Text(count == 0 ? '不重试'.tl : '$count ${'次'.tl}'),
                  ),
              ],
              onChanged: (value) => setState(() => _maxRetries = value ?? 3),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: App.globalBack, child: Text('取消'.tl)),
      FilledButton(onPressed: _save, child: Text('保存'.tl)),
    ],
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool obscureText = false,
    Widget? suffix,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
      ),
    ),
  );

  void _save() => Navigator.pop(
    context,
    widget.provider.copyWith(
      name: _name.text.trim(),
      protocol: _protocol,
      baseUrl: _baseUrl.text.trim(),
      apiKey: _apiKey.text.trim(),
      model: _model.text.trim(),
      reasoningEffort: _reasoningEffort,
      maxRetries: _maxRetries,
      clearReasoningEffort: _reasoningEffort == null,
    ),
  );
}

class _PromptEditorDialog extends StatefulWidget {
  final AiPromptPreset prompt;
  const _PromptEditorDialog({required this.prompt});

  @override
  State<_PromptEditorDialog> createState() => _PromptEditorDialogState();
}

class _PromptEditorDialogState extends State<_PromptEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _system;
  late final TextEditingController _user;
  late String _providerId;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.prompt.name);
    _system = TextEditingController(text: widget.prompt.systemPrompt);
    _user = TextEditingController(text: widget.prompt.userTemplate);
    _providerId = widget.prompt.providerId;
    _active = widget.prompt.isActive;
  }

  @override
  void dispose() {
    _name.dispose();
    _system.dispose();
    _user.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('编辑提示词'.tl),
    content: SizedBox(
      width: 580,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_name, '名称'.tl),
            DropdownButtonFormField<String>(
              value: _providerId,
              decoration: InputDecoration(labelText: 'AI服务'.tl),
              items: [
                DropdownMenuItem(value: '', child: Text('暂不绑定'.tl)),
                ...aiSettings.providers.map(
                  (item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                ),
              ],
              onChanged: (value) => setState(() => _providerId = value ?? ''),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('启用此提示词'.tl),
              value: _active,
              onChanged: (value) => setState(() => _active = value),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${'可用变量'.tl}：{{text}}、{{target_language}}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            _field(_system, 'System提示词'.tl, maxLines: 6),
            _field(_user, 'User模板'.tl, maxLines: 5),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: App.globalBack, child: Text('取消'.tl)),
      FilledButton(onPressed: _save, child: Text('保存'.tl)),
    ],
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  void _save() => Navigator.pop(
    context,
    widget.prompt.copyWith(
      name: _name.text.trim(),
      providerId: _providerId,
      systemPrompt: _system.text.trim(),
      userTemplate: _user.text.trim(),
      isActive: _active,
    ),
  );
}
