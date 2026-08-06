import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _maxMessageLength = 200;
const _nicknameKey = 'chat_nickname';

Future<void> ensureSignedIn() async {
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }
}

Future<String?> _getSavedNickname() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_nicknameKey);
}

Future<void> _saveNickname(String nickname) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_nicknameKey, nickname);
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _nickname;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await ensureSignedIn();
    final saved = await _getSavedNickname();
    if (!mounted) return;
    setState(() {
      _nickname = saved;
      _loading = false;
    });
    if (saved == null) {
      // Give the screen a frame to build before showing the dialog.
      WidgetsBinding.instance.addPostFrameCallback((_) => _promptNickname());
    }
  }

  Future<void> _promptNickname() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1c1c1e),
        title: Text(
          "Choose a nickname",
          style: GoogleFonts.montserrat(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "e.g. Luis",
            hintStyle: TextStyle(color: Colors.white38),
          ),
          onSubmitted: (value) {
            final text = value.trim();
            if (text.isNotEmpty) Navigator.pop(context, text);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(context, text);
            },
            child: const Text("Join chat"),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _saveNickname(result);
      if (!mounted) return;
      setState(() => _nickname = result);
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _nickname == null) return;
    if (text.length > _maxMessageLength) return;

    _controller.clear();

    await FirebaseFirestore.instance.collection('chat_messages').add({
      'text': text,
      'nickname': _nickname,
      'timestamp': FieldValue.serverTimestamp(),
      'uid': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          "Listener Chat",
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : _nickname == null
              ? Center(
                  child: ElevatedButton(
                    onPressed: _promptNickname,
                    child: const Text("Pick a nickname to join"),
                  ),
                )
              : SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('chat_messages')
                              .orderBy('timestamp', descending: true)
                              .limit(200)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Center(
                                child: Text(
                                  "Couldn't load chat.\n${snapshot.error}",
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.montserrat(
                                      color: Colors.white54),
                                ),
                              );
                            }
                            if (!snapshot.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white));
                            }

                            final docs = snapshot.data!.docs;
                            if (docs.isEmpty) {
                              return Center(
                                child: Text(
                                  "No messages yet — say hi!",
                                  style: GoogleFonts.montserrat(
                                      color: Colors.white54),
                                ),
                              );
                            }

                            return ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.all(12),
                              itemCount: docs.length,
                              itemBuilder: (context, index) {
                                final data =
                                    docs[index].data() as Map<String, dynamic>;
                                final msgNickname =
                                    data['nickname'] as String? ?? '???';
                                final text = data['text'] as String? ?? '';
                                final isMe = data['uid'] == myUid;

                                return Align(
                                  alignment: isMe
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                              0.75,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? Colors.blueAccent.withOpacity(0.85)
                                          : Colors.white12,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (!isMe)
                                          Text(
                                            msgNickname,
                                            style: GoogleFonts.montserrat(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        Text(
                                          text,
                                          style: GoogleFonts.montserrat(
                                            color: Colors.white,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                maxLength: _maxMessageLength,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  counterText: "",
                                  hintText: "Message as $_nickname",
                                  hintStyle:
                                      const TextStyle(color: Colors.white38),
                                  filled: true,
                                  fillColor: Colors.white10,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.send, color: Colors.white),
                              onPressed: _sendMessage,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
