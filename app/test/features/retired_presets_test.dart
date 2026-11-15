import 'package:dsh_app/state/new_chat_modes.dart';
import 'package:dsh_app/ui/chat/new_chat_options.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const regular = [
    AgentPresetInfo(id: 'standard'),
    AgentPresetInfo(id: 'ptc'),
    AgentPresetInfo(id: 'minimal'),
    AgentPresetInfo(id: 'cordis'),
    AgentPresetInfo(id: 'my-companion', name: '我自己的伙伴预设'),
  ];
  const retired = ['dsh-go-companion', 'dsh-go-companion-full', 'dsh-go-diagnostics'];

  test('all pickers omit retired feature presets without hiding custom user presets', () {
    final catalog = [...regular, for (final id in retired) AgentPresetInfo(id: id)];
    expect(selectableAgentPresets(catalog), regular);
    expect(newChatPresets(catalog), regular);
    expect(catalog, hasLength(8), reason: 'The Host catalog remains intact for default resolution.');
  });

  for (final id in retired) {
    test('retired Host default $id explicitly falls back before the first prompt', () {
      final catalog = [...regular, AgentPresetInfo(id: id, isDefault: true)];
      expect(newChatPresetToApply(catalog, null), 'standard');
      expect(newChatPresetToApply(catalog, id), 'standard');
      expect(newChatPresetToApply(null, id), 'standard');
      expect(newChatPresetToApply(catalog, 'my-companion'), 'my-companion');
    });

    test('saved unfinished setup $id keeps its other choices and leaves the retired mode', () {
      final setup = OwedSetup.fromJson({'preset': id, 'permission': 'read-only'});
      expect(setup.preset, 'standard');
      expect(setup.permission, 'read-only');
      expect(setup.toJson(), {'preset': 'standard', 'permission': 'read-only'});
    });
  }

  test('ordinary saved setups keep their custom preset', () {
    expect(OwedSetup.fromJson({'preset': 'my-companion', 'permission': 'read-only'}).preset, 'my-companion');
    expect(newChatPresetToApply(null, 'my-companion'), 'my-companion');
  });
}
