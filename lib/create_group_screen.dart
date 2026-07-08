import 'package:flutter/material.dart';
import 'main.dart';
import 'group_chat_screen.dart';

// ---------------------------------------------------------------------------
// Create a group: name it, pick friends, optionally add your robot, and choose
// what the group sees of your own messages. A group needs 3+ participants (the
// robot counts as one). On success it opens straight into the new group.
// ---------------------------------------------------------------------------

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  List<Map<String, dynamic>> _friends = [];
  final Set<int> _selected = {};
  bool _addRobot = false;
  String _robotName = 'Mia';
  int _sharePref = 1;
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await loadFriends();
    final robot = await loadRobotConfig();
    if (!mounted) return;
    setState(() {
      _friends = res['ok'] == true
          ? List<Map<String, dynamic>>.from(res['friends'] ?? [])
          : [];
      _robotName = (robot['name'] ?? 'Mia') as String;
      _loading = false;
    });
  }

  // Participants = me + picked friends + the robot (if added).
  int get _participantCount => 1 + _selected.length + (_addRobot ? 1 : 0);

  String _name(Map f) {
    final d = (f['displayName'] ?? '').toString();
    return d.isNotEmpty ? d : (f['username'] ?? '').toString();
  }

  Future<void> _create() async {
    if (_creating) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _snack('Please name the group.');
      return;
    }
    if (_participantCount < 3) {
      _snack('A group needs at least 3 people (the robot counts).');
      return;
    }
    setState(() => _creating = true);
    final robot = _addRobot ? await loadRobotConfig() : null;
    final res = await createGroup(
      name: name,
      memberUserIds: _selected.toList(),
      addRobot: _addRobot,
      robot: robot,
      sharePref: _sharePref,
    );
    if (!mounted) return;
    setState(() => _creating = false);
    if (res['ok'] == true) {
      final group = res['group'] as Map<String, dynamic>;
      // Replace this screen with the new group chat; popping returns to the
      // Groups tab, which reloads.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => GroupChatScreen(group: group)),
      );
    } else {
      _snack((res['error'] ?? 'Could not create the group.') as String);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Widget _prefTile(int value, String label) {
    final selected = _sharePref == value;
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? AppColors.navy : AppColors.tipText,
      ),
      title: Text(label),
      onTap: () => setState(() => _sharePref = value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New group'),
        actions: [
          TextButton(
            onPressed: _creating ? null : _create,
            child: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Create',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Group name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SwitchListTile(
                  secondary: const CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.navy,
                    child:
                        Icon(Icons.smart_toy, size: 18, color: Colors.white),
                  ),
                  title: Text('Add $_robotName (your robot)'),
                  subtitle:
                      const Text('Replies when someone mentions it by name'),
                  value: _addRobot,
                  onChanged: (v) => setState(() => _addRobot = v),
                ),
                const Divider(height: 1),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('ADD FRIENDS',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: AppColors.tipText)),
                ),
                if (_friends.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No friends yet. Add friends from the Friends tab first.',
                      style: TextStyle(color: AppColors.tipText),
                    ),
                  )
                else
                  ..._friends.map((f) {
                    final id = f['userId'] as int;
                    return CheckboxListTile(
                      value: _selected.contains(id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(id);
                        } else {
                          _selected.remove(id);
                        }
                      }),
                      title: Text(_name(f)),
                    );
                  }),
                const Divider(height: 1),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('WHAT THE GROUP SEES OF YOUR MESSAGES',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: AppColors.tipText)),
                ),
                for (final entry in groupShareLabels.entries)
                  _prefTile(entry.key, entry.value),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '$_participantCount participant'
                    '${_participantCount == 1 ? '' : 's'} so far '
                    '(need at least 3).',
                    style: const TextStyle(color: AppColors.tipText),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}
