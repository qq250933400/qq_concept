import 'avatars.dart';

/// 用户性别。与服务端 `users.gender` 对齐：0 保密 / 1 男 / 2 女。
enum QGender {
  secret(0, '保密'),
  male(1, '男'),
  female(2, '女');

  const QGender(this.code, this.label);

  final int code;
  final String label;

  static QGender fromCode(int? code) => switch (code) {
        1 => QGender.male,
        2 => QGender.female,
        _ => QGender.secret,
      };
}

/// 注册窗口的表单值对象。
///
/// 由 [QAppState.register] 一次性消费：文本字段留在注册窗的局部 State，
/// 提交时才拷贝进来，避免每敲一个字都通知全部 OS 窗口重建。
class QRegistration {
  const QRegistration({
    this.account = '',
    this.nickname = '',
    this.password = '',
    this.passwordConfirm = '',
    this.gender = QGender.secret,
    this.avatarIndex = 0,
  });

  final String account;
  final String nickname;
  final String password;
  final String passwordConfirm;
  final QGender gender;

  /// [kQBuiltinAvatars] 的下标；提交时转 `builtin://avatar/N` 存服务端。
  final int avatarIndex;

  QRegistration copyWith({
    String? account,
    String? nickname,
    String? password,
    String? passwordConfirm,
    QGender? gender,
    int? avatarIndex,
  }) =>
      QRegistration(
        account: account ?? this.account,
        nickname: nickname ?? this.nickname,
        password: password ?? this.password,
        passwordConfirm: passwordConfirm ?? this.passwordConfirm,
        gender: gender ?? this.gender,
        avatarIndex: avatarIndex ?? this.avatarIndex,
      );

  /// 提交前的前端校验；返回 null = 通过，否则返回中文错误文案。
  String? validate() {
    final acc = account.trim();
    if (acc.length < 3 || acc.length > 32) return '帐号需为 3 ~ 32 个字符';
    if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(acc)) {
      return '帐号仅支持字母、数字、下划线、点和短横线';
    }
    final nick = nickname.trim();
    if (nick.isEmpty || nick.length > 32) return '昵称需为 1 ~ 32 个字符';
    if (password.length < 6) return '密码至少 6 位';
    if (password != passwordConfirm) return '两次输入的密码不一致';
    return null;
  }
}
