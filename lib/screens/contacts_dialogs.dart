import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/contacts.dart';
import '../core/tokens.dart';
import '../core/widgets.dart';

/// 好友管理窗口内的关系链浮层。
///
/// 概念版本身没有这些对话框（原版靠气泡球与照片卡展示），这里沿用
/// 同一套深色玻璃 / 细线按钮语言补齐真实产品必备的操作：
/// 添加好友、好友申请、分组管理、移动好友、改名、删除确认。
/// 状态全部由 [QAppState] 持有，输入框文本留在各页的局部 State 里，
/// 避免每敲一个字都通知全部 OS 窗口重建。
class QContactsOverlay extends StatelessWidget {
  const QContactsOverlay({super.key, required this.state});

  final QAppState state;

  @override
  Widget build(BuildContext context) {
    final dialog = state.contactDialog;
    if (dialog == QContactDialog.none) return const SizedBox.shrink();
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: state.closeContactsDialog,
              child: const ColoredBox(color: Color(0xA3000000)),
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.03),
            child: Material(
              type: MaterialType.transparency,
              child: _card(dialog),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(QContactDialog dialog) => switch (dialog) {
        QContactDialog.addFriend => _frame(
            '添加好友',
            400,
            _AddFriendBody(state: state),
          ),
        QContactDialog.requests => _frame(
            '好友申请',
            400,
            _RequestsBody(state: state),
          ),
        QContactDialog.groups => _frame(
            '好友分组管理',
            400,
            _GroupsBody(state: state),
          ),
        QContactDialog.friendActions => _frame(
            '好友操作',
            280,
            _FriendActionsBody(state: state),
          ),
        QContactDialog.moveFriend => _frame(
            '移动到分组',
            340,
            _MoveFriendBody(state: state),
          ),
        QContactDialog.renameGroup => _frame(
            '重命名分组',
            215,
            _RenameGroupBody(state: state),
          ),
        QContactDialog.confirm => _frame(
            state.confirmTitle,
            210,
            _ConfirmBody(state: state),
          ),
        QContactDialog.none => const SizedBox.shrink(),
      };

  Widget _frame(String title, double height, Widget body) => DlgFrame(
        width: 480,
        height: height,
        title: title,
        dark: true,
        buttons: const [QWinBtnKind.close],
        onButtonTap: (_) => state.closeContactsDialog(),
        body: _surface(body),
      );

  /// DlgFrame 已经把 body 铺满整个卡片，标题栏画在其上，
  /// 因此这里返回普通 Container 而不是 Positioned（嵌套会断言失败）。
  Widget _surface(Widget child) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E2A3A), Color(0xFF001726)],
          ),
        ),
        padding: EdgeInsets.fromLTRB(18, S.dlgBarH + 12, 18, 16),
        child: child,
      );
}

// ---------------------------------------------------------------- 公共小部件
Widget _statusLine(QAppState state) {
  if (state.contactsBusy) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Text('正在处理…', style: TextStyle(color: Color(0xFF8FC7E8), fontSize: 11)),
    );
  }
  final error = state.contactsError;
  if (error == null) return const SizedBox(height: 4);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      error,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: QText.of(11, color: const Color(0xFFFF9B8A)),
    ),
  );
}

Widget _button(
  String label,
  VoidCallback? onTap, {
  double width = 76,
  bool danger = false,
}) {
  final enabled = onTap != null;
  final colors = !enabled
      ? <Color>[const Color(0xFF2C3B44), const Color(0xFF223039)]
      : danger
          ? <Color>[const Color(0xFF9B443A), const Color(0xFF6B2A24)]
          : <Color>[const Color(0xFF3C7391), const Color(0xFF234A60)];
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      width: width,
      height: 27,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0x66FFFFFF)),
        gradient: vg(colors),
      ),
      child: Text(
        label,
        style: QText.of(
          11,
          weight: FontWeight.w700,
          color: enabled ? QC.white : const Color(0xFF8FA0A9),
        ),
      ),
    ),
  );
}

Widget _field({
  required TextEditingController controller,
  required String hint,
  double width = 300,
  ValueChanged<String>? onSubmitted,
}) =>
    SizedBox(
      width: width,
      height: 30,
      child: TextField(
        controller: controller,
        onSubmitted: onSubmitted,
        style: QText.of(12),
        cursorColor: QC.white,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: const Color(0x66101E28),
          hintText: hint,
          hintStyle: QText.of(11, color: const Color(0xFF8CA3B2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Color(0x55FFFFFF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Color(0x55FFFFFF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Color(0xFF7FC4E8)),
          ),
        ),
      ),
    );

Widget _line(String text, {double size = 12, Color? color}) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: QText.of(size, color: color ?? QC.white),
    );

Widget _hint(String text) => Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: QText.of(11.5, color: const Color(0xFF9BB2BF)),
      ),
    );

Widget _listRow({
  required String title,
  String? subtitle,
  Widget? trailing,
  VoidCallback? onTap,
}) =>
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 46,
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          color: const Color(0x331B3A4B),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _line(title, size: 12),
                  if (subtitle != null && subtitle.isNotEmpty)
                    _line(subtitle, size: 10.5, color: const Color(0xFFA8C0CC)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );

// ---------------------------------------------------------------- 添加好友
class _AddFriendBody extends StatefulWidget {
  const _AddFriendBody({required this.state});
  final QAppState state;

  @override
  State<_AddFriendBody> createState() => _AddFriendBodyState();
}

class _AddFriendBodyState extends State<_AddFriendBody> {
  final TextEditingController _query = TextEditingController();
  final TextEditingController _message = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    _message.dispose();
    super.dispose();
  }

  void _search() {
    FocusScope.of(context).unfocus();
    widget.state.searchUsersForAdd(_query.text);
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final results = st.searchResults;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _line('输入对方帐号或昵称查找，发送申请后等待对方通过。',
            size: 11, color: const Color(0xFFA8C0CC)),
        const SizedBox(height: 10),
        Row(
          children: [
            _field(
              controller: _query,
              hint: 'QQ 帐号 / 昵称',
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(width: 10),
            _button('查找', st.contactsBusy ? null : _search),
          ],
        ),
        _statusLine(st),
        const SizedBox(height: 4),
        Expanded(
          child: results.isEmpty
              ? _hint('还没有搜索结果\n演示账号 10001 ~ 10010')
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final hit = results[i];
                    return _listRow(
                      title: '${hit.name}  (${hit.account})',
                      subtitle: hit.signature.isEmpty ? '暂无签名' : hit.signature,
                      trailing: hit.isFriend
                          ? _line('已是好友',
                              size: 10.5, color: const Color(0xFF9BB2BF))
                          : _button(
                              '添加',
                              st.contactsBusy
                                  ? null
                                  : () => st.sendFriendRequest(
                                      hit.account, _message.text),
                              width: 62,
                            ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _field(
              controller: _message,
              hint: '验证消息（选填）',
              width: 290,
              onSubmitted: (_) {},
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _line('点结果右侧「添加」发送申请',
                  size: 10.5, color: const Color(0xFF9BB2BF)),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 好友申请
class _RequestsBody extends StatefulWidget {
  const _RequestsBody({required this.state});
  final QAppState state;

  @override
  State<_RequestsBody> createState() => _RequestsBodyState();
}

class _RequestsBodyState extends State<_RequestsBody> {
  String _direction = 'in';

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final rows = st.friendRequests
        .where((r) => r.direction == _direction)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _button(
              '收到的 (${st.friendRequests.where((r) => r.direction == 'in').length})',
              () => setState(() => _direction = 'in'),
              width: 100,
            ),
            const SizedBox(width: 8),
            _button(
              '发出的 (${st.friendRequests.where((r) => r.direction == 'out').length})',
              () => setState(() => _direction = 'out'),
              width: 100,
            ),
            const Spacer(),
            _button('刷新', st.contactsBusy ? null : st.refreshContacts,
                width: 62),
          ],
        ),
        _statusLine(st),
        const SizedBox(height: 6),
        Expanded(
          child: rows.isEmpty
              ? _hint(_direction == 'in'
                  ? '暂时没有收到好友申请'
                  : '还没有发出好友申请')
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final statusText = r.status == 0
                        ? (_direction == 'in' ? '等待你处理' : '等待对方处理')
                        : (r.status == 1 ? '已通过' : '已拒绝');
                    return _listRow(
                      title: '${r.name}  (${r.account})',
                      subtitle: r.message.isEmpty ? statusText : '${r.message} · $statusText',
                      trailing: r.pending
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _button(
                                  '通过',
                                  st.contactsBusy
                                      ? null
                                      : () => st.acceptFriendRequest(r.id),
                                  width: 56,
                                ),
                                const SizedBox(width: 6),
                                _button(
                                  '拒绝',
                                  st.contactsBusy
                                      ? null
                                      : () => st.rejectFriendRequest(r.id),
                                  width: 56,
                                  danger: true,
                                ),
                              ],
                            )
                          : _line(statusText,
                              size: 10.5, color: const Color(0xFF9BB2BF)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 分组管理
class _GroupsBody extends StatefulWidget {
  const _GroupsBody({required this.state});
  final QAppState state;

  @override
  State<_GroupsBody> createState() => _GroupsBodyState();
}

class _GroupsBodyState extends State<_GroupsBody> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final groups = st.contactGroups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _line('分组可新建、改名、删除；删除后组内好友回到「未分组」。',
            size: 11, color: const Color(0xFFA8C0CC)),
        const SizedBox(height: 8),
        Expanded(
          child: groups.isEmpty
              ? _hint('还没有分组，先在下面新建一个吧')
              : ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, i) {
                    final g = groups[i];
                    final virtual = g.id.isEmpty;
                    return _listRow(
                      title: g.name,
                      subtitle: '${g.count} 位好友',
                      trailing: virtual
                          ? _line('系统分组',
                              size: 10.5, color: const Color(0xFF9BB2BF))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _button(
                                  '改名',
                                  st.contactsBusy
                                      ? null
                                      : () => st.openContactsDialog(
                                          QContactDialog.renameGroup,
                                          target: g.id,
                                          targetName: g.name,
                                        ),
                                  width: 56,
                                ),
                                const SizedBox(width: 6),
                                _button(
                                  '删除',
                                  st.contactsBusy
                                      ? null
                                      : () => st.askConfirm(
                                          title: '删除分组',
                                          message: '确定删除「${g.name}」吗？组内好友会移到未分组。',
                                          action: 'deleteGroup',
                                          target: g.id,
                                        ),
                                  width: 56,
                                  danger: true,
                                ),
                              ],
                            ),
                    );
                  },
                ),
        ),
        _statusLine(st),
        Row(
          children: [
            _field(
              controller: _name,
              hint: '新分组名称',
              onSubmitted: (_) {
                st.createFriendGroup(_name.text);
                _name.clear();
              },
            ),
            const SizedBox(width: 10),
            _button(
              '新建分组',
              st.contactsBusy
                  ? null
                  : () {
                      st.createFriendGroup(_name.text);
                      _name.clear();
                    },
              width: 88,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 好友操作
class _FriendActionsBody extends StatelessWidget {
  const _FriendActionsBody({required this.state});
  final QAppState state;

  @override
  Widget build(BuildContext context) {
    final name = state.dialogTarget ?? state.dialogTargetName ?? '';
    final contact = state.contactByName(name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _line('${contact?.name ?? name}  ${contact?.account ?? ''}', size: 13),
        if (contact != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _line(contact.signature,
                size: 11, color: const Color(0xFFA8C0CC)),
          ),
        const SizedBox(height: 14),
        _listRow(
          title: '打开聊天窗口',
          subtitle: '与 TA 开始会话',
          onTap: () {
            state.closeContactsDialog();
            state.selectFriend(name);
          },
        ),
        _listRow(
          title: '移动到分组…',
          subtitle: '选择目标分组',
          onTap: () => state.openContactsDialog(
            QContactDialog.moveFriend,
            target: name,
          ),
        ),
        _listRow(
          title: '移回未分组',
          subtitle: '从当前分组移出',
          onTap: () => state.moveFriend(name, null),
        ),
        _listRow(
          title: '删除好友',
          subtitle: '双向解除好友关系',
          onTap: () => state.askConfirm(
            title: '删除好友',
            message: '确定删除「$name」吗？聊天记录仍会保留在服务端。',
            action: 'deleteFriend',
            target: name,
          ),
        ),
        _statusLine(state),
      ],
    );
  }
}

// ---------------------------------------------------------------- 移动分组
class _MoveFriendBody extends StatelessWidget {
  const _MoveFriendBody({required this.state});
  final QAppState state;

  @override
  Widget build(BuildContext context) {
    final name = state.dialogTarget ?? '';
    final contact = state.contactByName(name);
    final current = contact?.groupId ?? '';
    final groups = state.contactGroups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _line('把「$name」移动到：', size: 11.5,
            color: const Color(0xFFA8C0CC)),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: [
              _listRow(
                title: '未分组',
                subtitle: '不归属任何分组',
                trailing: current.isEmpty
                    ? _line('当前', size: 10.5, color: const Color(0xFF7FC4E8))
                    : null,
                onTap: () => state.moveFriend(name, null),
              ),
              for (final g in groups)
                if (g.id.isNotEmpty)
                  _listRow(
                    title: g.name,
                    subtitle: '${g.count} 位好友',
                    trailing: current == g.id
                        ? _line('当前', size: 10.5, color: const Color(0xFF7FC4E8))
                        : null,
                    onTap: () => state.moveFriend(name, g.id),
                  ),
            ],
          ),
        ),
        _statusLine(state),
      ],
    );
  }
}

// ---------------------------------------------------------------- 重命名分组
class _RenameGroupBody extends StatefulWidget {
  const _RenameGroupBody({required this.state});
  final QAppState state;

  @override
  State<_RenameGroupBody> createState() => _RenameGroupBodyState();
}

class _RenameGroupBodyState extends State<_RenameGroupBody> {
  late final TextEditingController _name =
      TextEditingController(text: widget.state.dialogTargetName ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _line('输入新的分组名称', size: 11.5,
            color: const Color(0xFFA8C0CC)),
        const SizedBox(height: 12),
        _field(controller: _name, hint: '分组名称', width: 440),
        _statusLine(st),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _button('取消', st.closeContactsDialog),
            const SizedBox(width: 8),
            _button(
              '保存',
              st.contactsBusy
                  ? null
                  : () => st.renameFriendGroup(
                      st.dialogTarget ?? '', _name.text),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 确认
class _ConfirmBody extends StatelessWidget {
  const _ConfirmBody({required this.state});
  final QAppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Text(
          state.confirmMessage,
          style: QText.of(12.5).copyWith(height: 1.5),
        ),
        _statusLine(state),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _button('取消', state.closeContactsDialog),
            const SizedBox(width: 8),
            _button('确定', state.runConfirm, danger: true),
          ],
        ),
      ],
    );
  }
}
