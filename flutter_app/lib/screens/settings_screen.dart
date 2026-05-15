import 'package:flutter/material.dart';
import 'package:backtester_shell/services/api_service.dart';
import 'package:backtester_shell/services/app_settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final ApiService apiService;
  final AppSettings initialSettings;
  final ValueChanged<AppSettings>? onSaved;
  const SettingsScreen({
    super.key,
    required this.apiService,
    required this.initialSettings,
    this.onSaved,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _settings;
  final AppSettingsService _settingsService = AppSettingsService();
  bool _credsExist = false;
  bool _loading = true;
  String? _savedMsg;

  final _apiKeyCtrl = TextEditingController();
  final _apiSecretCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _apiSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final settings = AppSettings.fromJson(widget.initialSettings.toJson());
    bool credsExist = false;
    try {
      credsExist = await widget.apiService.credentialsExist();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _settings = settings;
        _credsExist = credsExist;
        _loading = false;
      });
    }
  }

  void _saveToDisk() {
    try {
      _settingsService.save(_settings);
      widget.onSaved?.call(AppSettings.fromJson(_settings.toJson()));
      setState(() => _savedMsg = 'Settings saved ✓');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _savedMsg = null);
      });
    } catch (e) {
      setState(() => _savedMsg = 'Error: $e');
    }
  }

  Future<void> _saveCredentials() async {
    final key = _apiKeyCtrl.text.trim();
    final secret = _apiSecretCtrl.text.trim();
    if (key.isEmpty || secret.isEmpty) return;
    try {
      await widget.apiService.saveCredentials(key, secret);
      _apiKeyCtrl.clear();
      _apiSecretCtrl.clear();
      if (mounted) {
        setState(() => _credsExist = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('API credentials saved'),
            backgroundColor: Color(0xFF26a69a),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: const Color(0xFFef5350)),
        );
      }
    }
  }

  Future<void> _deleteCredentials() async {
    try {
      await widget.apiService.deleteCredentials();
      if (mounted) {
        setState(() => _credsExist = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('API credentials deleted'),
            backgroundColor: Color(0xFFef5350),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: const Color(0xFFef5350)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF26a69a)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Row(
                children: [
                  const Icon(Icons.settings, color: Color(0xFF787B86), size: 28),
                  const SizedBox(width: 12),
                  const Text(
                    'Settings',
                    style: TextStyle(
                      color: Color(0xFFD9D9D9),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_savedMsg != null)
                    Text(
                      _savedMsg!,
                      style: TextStyle(
                        color: _savedMsg!.startsWith('Error')
                            ? const Color(0xFFef5350)
                            : const Color(0xFF26a69a),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 28),

              // ── Connection ──
              _SectionCard(
                title: 'CONNECTION',
                icon: Icons.lan_outlined,
                children: [
                  _SettingsField(
                    label: 'Backend URL',
                    value: _settings.backendUrl,
                    hint: 'http://127.0.0.1:8002',
                    onChanged: (v) => _settings.backendUrl = v,
                  ),
                  const SizedBox(height: 12),
                  _SettingsField(
                    label: 'API Token (optional)',
                    value: _settings.apiToken,
                    hint: 'Matches BACKTESTER_API_TOKEN',
                    obscure: true,
                    onChanged: (v) => _settings.apiToken = v,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Backtest Defaults ──
              _SectionCard(
                title: 'BACKTEST DEFAULTS',
                icon: Icons.candlestick_chart_outlined,
                children: [
                  _SettingsField(
                    label: 'Initial Cash (USDT)',
                    value: _settings.defaultCash.toString(),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final n = double.tryParse(v);
                      if (n != null) _settings.defaultCash = n;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SettingsField(
                          label: 'Taker Fee %',
                          value: _settings.defaultFeePct.toString(),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            final n = double.tryParse(v);
                            if (n != null) _settings.defaultFeePct = n;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _SettingsField(
                          label: 'Slippage %',
                          value: _settings.defaultSlippagePct.toString(),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            final n = double.tryParse(v);
                            if (n != null) _settings.defaultSlippagePct = n;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Binance API Credentials ──
              _SectionCard(
                title: 'BINANCE API CREDENTIALS',
                icon: Icons.vpn_key_outlined,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _credsExist
                              ? const Color(0xFF26a69a)
                              : const Color(0xFFef5350),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _credsExist
                            ? 'Credentials are stored in the vault'
                            : 'No credentials configured',
                        style: TextStyle(
                          color: _credsExist
                              ? const Color(0xFF26a69a)
                              : const Color(0xFF787B86),
                          fontSize: 12,
                        ),
                      ),
                      if (_credsExist) ...[
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _deleteCredentials,
                          icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFef5350)),
                          label: const Text('Delete', style: TextStyle(color: Color(0xFFef5350), fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                  if (!_credsExist) ...[
                    const SizedBox(height: 12),
                    _SettingsField(
                      label: 'API Key',
                      controller: _apiKeyCtrl,
                      hint: 'Paste your Binance API key',
                      obscure: true,
                    ),
                    const SizedBox(height: 8),
                    _SettingsField(
                      label: 'API Secret',
                      controller: _apiSecretCtrl,
                      hint: 'Paste your Binance API secret',
                      obscure: true,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _saveCredentials,
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('Save Credentials'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF26a69a),
                          minimumSize: const Size(0, 34),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 32),

              // ── Save button ──
              Center(
                child: FilledButton.icon(
                  onPressed: _saveToDisk,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Save Settings'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFb388ff),
                    minimumSize: const Size(200, 42),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Version footer ──
              Center(
                child: Text(
                  'Backtester Shell  v1.3  •  Phase 6',
                  style: TextStyle(
                    color: const Color(0xFF787B86).withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section Card ──────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2B2B43)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF787B86), size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF787B86),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

// ── Settings Field ────────────────────────────────────────────

class _SettingsField extends StatelessWidget {
  final String label;
  final String? value;
  final String? hint;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final bool obscure;
  final ValueChanged<String>? onChanged;

  const _SettingsField({
    required this.label,
    this.value,
    this.hint,
    this.controller,
    this.keyboardType,
    this.obscure = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF787B86), fontSize: 11)),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          initialValue: controller == null ? value : null,
          keyboardType: keyboardType,
          obscureText: obscure,
          style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF4A4A5A), fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF131722),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF2B2B43)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF2B2B43)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF26a69a)),
            ),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
