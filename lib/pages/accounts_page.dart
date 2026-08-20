import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:url_launcher/url_launcher_string.dart';

part 'accounts_page.g.dart';

/// 账号管理页面状态。
class AccountsPageState {
  const AccountsPageState({this.reLogin = const {}});

  final Map<String, bool> reLogin;

  /// 创建更新后的页面状态。
  AccountsPageState copyWith({Map<String, bool>? reLogin}) {
    return AccountsPageState(reLogin: reLogin ?? this.reLogin);
  }
}

/// 账号管理页面逻辑。
@Riverpod(keepAlive: false)
class AccountsPageLogic extends _$AccountsPageLogic {
  @override
  AccountsPageState build() => const AccountsPageState();

  /// 更新指定账号的重新登录状态。
  void setRelogin(String key, bool value) {
    final reLogin = Map<String, bool>.from(state.reLogin)..[key] = value;
    state = state.copyWith(reLogin: Map.unmodifiable(reLogin));
  }

  /// 通知页面重新读取漫画源账号信息。
  void refresh() {
    state = state.copyWith(
      reLogin: Map.unmodifiable(Map<String, bool>.from(state.reLogin)),
    );
  }
}

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageState = ref.watch(accountsPageLogicProvider);
    final logic = ref.read(accountsPageLogicProvider.notifier);
    final body = CustomScrollView(
      slivers: [
        SliverList(
          delegate: SliverChildListDelegate(
            buildContent(context, pageState, logic).toList(),
          ),
        ),
        SliverPadding(padding: EdgeInsets.only(bottom: context.padding.bottom)),
      ],
    );

    if (PopupIndicatorWidget.maybeOf(context) != null) {
      return PopUpWidgetScaffold(title: "账号管理".tl, body: body);
    } else {
      return Scaffold(
        appBar: AppBar(title: Text("账号管理".tl)),
        body: body,
      );
    }
  }

  Iterable<Widget> buildContent(
    BuildContext context,
    AccountsPageState pageState,
    AccountsPageLogic logic,
  ) sync* {
    var sources = ComicSource.sources.where(
      (element) => element.account != null,
    );
    if (sources.isEmpty) return;

    for (var element in sources) {
      final bool logged = element.isLogin;
      yield Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(element.name.tl, style: const TextStyle(fontSize: 20)),
      );
      if (!logged) {
        yield ListTile(
          title: Text("登录".tl),
          onTap: () async {
            if (element.account!.onLogin != null) {
              await element.account!.onLogin!(context);
            }
            if (element.account!.login != null && context.mounted) {
              await context.to(
                () => _LoginPage(
                  login: element.account!.login!,
                  registerWebsite: element.account!.registerWebsite,
                ),
              );
              element.saveData();
            }
            if (context.mounted) {
              logic.refresh();
            }
          },
        );
      }
      if (logged) {
        for (var item in element.account!.infoItems) {
          if (item.builder != null) {
            yield item.builder!(context);
          } else {
            yield ListTile(
              title: Text(item.title.tl),
              subtitle: item.data == null ? null : Text(item.data!()),
              onTap: item.onTap,
            );
          }
        }
        if (element.account!.allowReLogin) {
          bool loading = pageState.reLogin[element.key.name] == true;
          yield ListTile(
            title: Text("重新登录".tl),
            subtitle: Text("如果登录失效点击此处".tl),
            onTap: () async {
              if (element.data["account"] == null) {
                showToast(message: "无数据".tl);
                return;
              }
              logic.setRelogin(element.key.name, true);
              final List account = element.data["account"];
              try {
                var res = await element.account!.login!(account[0], account[1]);
                if (res.error) {
                  showToast(message: res.errorMessage!);
                } else {
                  showToast(message: "重新登录成功".tl);
                }
              } finally {
                if (context.mounted) {
                  logic.setRelogin(element.key.name, false);
                }
              }
            },
            trailing: loading
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          );
        }
        yield ListTile(
          title: Text("退出登录".tl),
          onTap: () {
            element.data["account"] = null;
            element.account?.logout();
            element.saveData();
            logic.refresh();
          },
          trailing: const Icon(Icons.logout),
        );
      }
      yield const Divider();
    }
  }

  void setClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showToast(message: "已复制".tl, icon: const Icon(Icons.check));
  }
}

class _LoginPage extends StatefulWidget {
  const _LoginPage({required this.login, this.registerWebsite});

  final LoginFunction login;

  final String? registerWebsite;

  @override
  State<_LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<_LoginPage> {
  String username = "";
  String password = "";
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Appbar(title: Text("登录".tl)),
      body: Column(
        children: [
          const Spacer(),
          TextField(
            decoration: InputDecoration(
              labelText: "用户名".tl,
              border: const OutlineInputBorder(),
            ),
            onChanged: (s) {
              username = s;
            },
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              labelText: "密码".tl,
              border: const OutlineInputBorder(),
            ),
            obscureText: true,
            onChanged: (s) {
              password = s;
            },
            onSubmitted: (s) => login(),
          ),
          const SizedBox(height: 32),
          Button.filled(
            isLoading: loading,
            onPressed: login,
            child: Text("继续".tl),
          ),
          const Spacer(),
          if (widget.registerWebsite != null)
            TextButton(
              onPressed: () => launchUrlString(widget.registerWebsite!),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("注册".tl),
                  const SizedBox(width: 4),
                  const Icon(Icons.open_in_new, size: 16),
                ],
              ),
            ),
          if (UiMode.m1(context))
            SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ).paddingLeft(32).paddingRight(32).paddingBottom(16),
    );
  }

  void login() {
    if (username.isEmpty || password.isEmpty) {
      showToast(message: "不能为空".tl, icon: const Icon(Icons.error_outline));
      return;
    }
    setState(() {
      loading = true;
    });
    widget.login(username, password).then((value) {
      if (value.error) {
        showToast(message: value.errorMessage!);
        setState(() {
          loading = false;
        });
      } else {
        showToast(message: "登录成功".tl, icon: const Icon(Icons.check));
        if (mounted) {
          context.pop();
        }
      }
    });
  }
}
