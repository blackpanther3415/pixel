import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class VaultService {
  static const _saltLength = 16;
  static const _ivLength = 12;

  SecretKey? _key;
  Uint8List? _salt;

  bool get isLocked => _key == null;
  bool get hasSalt => _salt != null;

  void loadSalt(String? b64Salt) {
    if (b64Salt != null && b64Salt.isNotEmpty) {
      _salt = base64Decode(b64Salt);
    }
  }

  Future<bool> unlock(String passphrase) async {
    if (passphrase.isEmpty) return false;
    _salt ??= _randomBytes(_saltLength);
    final salt = _salt!;
    final ikm = utf8.encode(passphrase);
    final secretKey = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 200000,
      bits: 256,
    ).deriveKey(
      secretKey: SecretKey(ikm),
      nonce: salt,
    );
    _key = secretKey;
    return true;
  }

  void lock() {
    _key = null;
  }

  Future<String?> rekey(String oldPass, String newPass, String encryptedB64) async {
    final plain = await decrypt(encryptedB64);
    if (plain == null) return null;
    final oldSalt = _salt;
    _salt = _randomBytes(_saltLength);
    await unlock(newPass);
    final result = await encrypt(plain);
    _salt = oldSalt;
    return result;
  }

  Future<String> encrypt(String plaintext) async {
    if (_key == null) throw StateError('Vault is locked');
    final aesGcm = AesGcm.with256bits();
    final iv = _randomBytes(_ivLength);
    final secretBox = await aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: _key!,
      nonce: iv,
    );
    final packed = Uint8List(iv.length + secretBox.cipherText.length + secretBox.mac.bytes.length);
    packed.setAll(0, iv);
    packed.setAll(iv.length, secretBox.cipherText);
    packed.setAll(iv.length + secretBox.cipherText.length, secretBox.mac.bytes);
    return base64Encode(packed);
  }

  Future<String?> decrypt(String encryptedB64) async {
    if (_key == null) return null;
    try {
      final packed = base64Decode(encryptedB64);
      if (packed.length < _ivLength) return null;
      final iv = packed.sublist(0, _ivLength);
      final rest = packed.sublist(_ivLength);
      const tagLen = 16;
      if (rest.length < tagLen) return null;
      final cipherText = rest.sublist(0, rest.length - tagLen);
      final mac = Mac(rest.sublist(rest.length - tagLen));
      final secretBox = SecretBox(cipherText, nonce: iv, mac: mac);
      final aesGcm = AesGcm.with256bits();
      final clearBytes = await aesGcm.decrypt(secretBox, secretKey: _key!);
      return utf8.decode(clearBytes);
    } catch (_) {
      return null;
    }
  }

  Future<String> maybeEncrypt(String plaintext) async {
    if (_key == null) return plaintext;
    return encrypt(plaintext);
  }

  Future<String> maybeDecrypt(String encrypted) async {
    if (_key == null) return encrypted;
    final result = await decrypt(encrypted);
    return result ?? encrypted;
  }

  String? get saltB64 => _salt != null ? base64Encode(_salt!) : null;

  Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }
}
