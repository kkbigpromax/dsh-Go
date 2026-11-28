// 设置 › 代理: one VLESS + REALITY server typed in by hand, run by the bundled
// Xray core so the engine's model requests go through it (Android only).
// The native side (proxy/XrayProxy.kt) owns storage and the process; this is
// the channel and the model the page edits.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The server, as `proxy/XrayConfig.kt` stores it.
class ProxyConfig {
  const ProxyConfig({
    this.enabled = false,
    this.address = '',
    this.port = 443,
    this.id = '',
    this.encryption = 'none',
    this.flow = visionFlow,
    this.network = raw,
    this.sni = '',
    this.fingerprint = 'chrome',
    this.publicKey = '',
    this.shortId = '',
    this.spiderX = '',
    this.mldsa65Verify = '',
    this.xhttpHost = '',
    this.xhttpPath = '/',
    this.xhttpMode = 'auto',
  });

  static const raw = 'raw';
  static const xhttp = 'xhttp';
  static const visionFlow = 'xtls-rprx-vision';
  static const xhttpModes = ['auto', 'packet-up', 'stream-up', 'stream-one'];
  static const fingerprints = [
    'chrome',
    'firefox',
    'safari',
    'ios',
    'android',
    'edge',
    '360',
    'qq',
    'random',
    'randomized',
  ];

  final bool enabled;
  final String address;
  final int port;
  final String id;
  final String encryption;
  final String flow;
  final String network;
  final String sni;
  final String fingerprint;
  final String publicKey;
  final String shortId;
  final String spiderX;
  final String mldsa65Verify;
  final String xhttpHost;
  final String xhttpPath;
  final String xhttpMode;

  /// The first missing or wrong field (the same codes as the native side), or null.
  String? get problem {
    if (address.trim().isEmpty) return 'address';
    if (port < 1 || port > 65535) return 'port';
    if (id.trim().isEmpty) return 'id';
    if (publicKey.trim().isEmpty) return 'publicKey';
    return null;
  }

  ProxyConfig copyWith({
    bool? enabled,
    String? address,
    int? port,
    String? id,
    String? encryption,
    String? flow,
    String? network,
    String? sni,
    String? fingerprint,
    String? publicKey,
    String? shortId,
    String? spiderX,
    String? mldsa65Verify,
    String? xhttpHost,
    String? xhttpPath,
    String? xhttpMode,
  }) => ProxyConfig(
    enabled: enabled ?? this.enabled,
    address: address ?? this.address,
    port: port ?? this.port,
    id: id ?? this.id,
    encryption: encryption ?? this.encryption,
    flow: flow ?? this.flow,
    network: network ?? this.network,
    sni: sni ?? this.sni,
    fingerprint: fingerprint ?? this.fingerprint,
    publicKey: publicKey ?? this.publicKey,
    shortId: shortId ?? this.shortId,
    spiderX: spiderX ?? this.spiderX,
    mldsa65Verify: mldsa65Verify ?? this.mldsa65Verify,
    xhttpHost: xhttpHost ?? this.xhttpHost,
    xhttpPath: xhttpPath ?? this.xhttpPath,
    xhttpMode: xhttpMode ?? this.xhttpMode,
  );

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'address': address.trim(),
    'port': port,
    'id': id.trim(),
    'encryption': encryption.trim(),
    'flow': flow,
    'network': network,
    'sni': sni.trim(),
    'fingerprint': fingerprint,
    'publicKey': publicKey.trim(),
    'shortId': shortId.trim(),
    'spiderX': spiderX.trim(),
    'mldsa65Verify': mldsa65Verify.trim(),
    'xhttpHost': xhttpHost.trim(),
    'xhttpPath': xhttpPath.trim(),
    'xhttpMode': xhttpMode,
  };

  factory ProxyConfig.fromJson(Map<String, Object?> json) {
    const d = ProxyConfig();
    String s(String key, String fallback) => json[key] is String ? json[key]! as String : fallback;
    return ProxyConfig(
      enabled: json['enabled'] == true,
      address: s('address', d.address),
      port: json['port'] is int ? json['port']! as int : d.port,
      id: s('id', d.id),
      encryption: s('encryption', d.encryption),
      flow: s('flow', d.flow),
      network: s('network', d.network),
      sni: s('sni', d.sni),
      fingerprint: s('fingerprint', d.fingerprint),
      publicKey: s('publicKey', d.publicKey),
      shortId: s('shortId', d.shortId),
      spiderX: s('spiderX', d.spiderX),
      mldsa65Verify: s('mldsa65Verify', d.mldsa65Verify),
      xhttpHost: s('xhttpHost', d.xhttpHost),
      xhttpPath: s('xhttpPath', d.xhttpPath),
      xhttpMode: s('xhttpMode', d.xhttpMode),
    );
  }

  @override
  bool operator ==(Object other) => other is ProxyConfig && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// What the native side says: the saved server, whether this build carries the
/// core, and how the last engine launch went.
class ProxyState {
  const ProxyState({required this.config, required this.available, this.running = false, this.error});
  final ProxyConfig config;
  final bool available;
  final bool running;
  final String? error;
}

/// A connection test: the time it took, or why it failed.
class ProxyTestResult {
  const ProxyTestResult({this.ms, this.error});
  final int? ms;
  final String? error;
}

class ProxyChannel {
  const ProxyChannel([this._channel = const MethodChannel('dsh/proxy')]);
  final MethodChannel _channel;

  Future<ProxyState> load() async {
    final raw = await _channel.invokeMapMethod<String, Object?>('load') ?? const {};
    final config = raw['config'] is String ? jsonDecode(raw['config']! as String) : null;
    return ProxyState(
      config: config is Map<String, Object?> ? ProxyConfig.fromJson(config) : const ProxyConfig(),
      available: raw['available'] == true,
      running: raw['running'] == true,
      error: raw['error'] as String?,
    );
  }

  /// Null when saved; otherwise the field the native side refused.
  Future<String?> save(ProxyConfig config) => _channel.invokeMethod<String>('save', jsonEncode(config.toJson()));

  Future<ProxyTestResult> test(ProxyConfig config) async {
    final raw = await _channel.invokeMapMethod<String, Object?>('test', jsonEncode(config.toJson())) ?? const {};
    return ProxyTestResult(ms: (raw['ms'] as num?)?.toInt(), error: raw['error'] as String?);
  }
}

final proxyChannelProvider = Provider<ProxyChannel>((ref) => const ProxyChannel());

/// The saved proxy, read again whenever the page saves.
final proxyStateProvider = FutureProvider.autoDispose<ProxyState>((ref) => ref.watch(proxyChannelProvider).load());
