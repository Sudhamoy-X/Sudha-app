import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SudhaApp());
}

class SudhaApp extends StatelessWidget {
  const SudhaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sudha',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        primaryColor: const Color(0xFF00FFC2),
      ),
      home: const SudhaBrowserScreen(),
    );
  }
}

class SudhaBrowserScreen extends StatefulWidget {
  const SudhaBrowserScreen({super.key});

  @override
  State<SudhaBrowserScreen> createState() => _SudhaBrowserScreenState();
}

class _SudhaBrowserScreenState extends State<SudhaBrowserScreen> {
  InAppWebViewController? webViewController;
  late IO.Socket socket;
  
  final String roomId = "sudha-demo-room";
  bool isWebLoaded = false;
  bool isMirrorMode = false;
  
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, String>> chatMessages = [];

  @override
  void initState() {
    super.initState();
    _connectSocket();
  }

  void _connectSocket() {
    socket = IO.io("https://sudha-sync.glitch.me", IO.OptionBuilder().setTransports(['websocket']).build());
    socket.onConnect((_) => socket.emit("join-room", roomId));

    socket.on("on-sync-url", (url) {
      if (!isMirrorMode) {
        webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      }
    });

    socket.on("on-sync-video", (data) {
      if (!isMirrorMode && webViewController != null) {
        String action = data['action'];
        num time = data['time'];
        if (action == 'PLAY') {
          webViewController?.evaluateJavascript(source: "document.querySelector('video')?.play();");
        } else if (action == 'PAUSE') {
          webViewController?.evaluateJavascript(source: "document.querySelector('video')?.pause();");
        } else if (action == 'SEEK') {
          webViewController?.evaluateJavascript(source: "var v = document.querySelector('video'); if(v) v.currentTime = $time;");
        }
      }
    });

    socket.on("on-receive-chat", (data) {
      setState(() {
        chatMessages.add({
          "sender": data['sender'],
          "message": data['message'],
        });
      });
    });
  }

  void _injectVideoSyncScript() {
    const jsCode = """
      (function() {
        if (window._sudhaInjected) return;
        window._sudhaInjected = true;
        setInterval(() => {
          const video = document.querySelector('video');
          if (video && !video._hasSudhaListener) {
            video._hasSudhaListener = true;
            video.addEventListener('play', () => window.flutter_inappwebview.callHandler('onVideoEvent', 'PLAY', video.currentTime));
            video.addEventListener('pause', () => window.flutter_inappwebview.callHandler('onVideoEvent', 'PAUSE', video.currentTime));
            video.addEventListener('seeked', () => window.flutter_inappwebview.callHandler('onVideoEvent', 'SEEK', video.currentTime));
          }
        }, 1000);
      })();
    """;
    webViewController?.evaluateJavascript(source: jsCode);
  }

  void _loadUrl(String input) {
    String url = input.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://www.google.com/search?q=$url';
    }
    webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    socket.emit("sync-url", {"roomId": roomId, "url": url});
    setState(() => isWebLoaded = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            isWebLoaded
                ? InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri("https://google.com")),
                    onWebViewCreated: (controller) {
                      webViewController = controller;
                      controller.addJavaScriptHandler(
                        handlerName: 'onVideoEvent',
                        callback: (args) {
                          if (!isMirrorMode) {
                            socket.emit("sync-video", {
                              "roomId": roomId,
                              "action": args[0],
                              "time": args[1],
                            });
                          }
                        },
                      );
                    },
                    onLoadStop: (controller, url) => _injectVideoSyncScript(),
                  )
                : _buildGlowingHome(),
            Positioned(top: 10, left: 15, right: 15, child: _buildTopControl()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF00FFC2),
        mini: true,
        onPressed: _openChatModal,
        child: const Icon(Icons.chat_bubble_outline, color: Colors.black),
      ),
    );
  }

  Widget _buildGlowingHome() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00FFC2).withOpacity(0.4),
                  blurRadius: 50,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: const Text('S', style: TextStyle(fontSize: 100, fontWeight: FontWeight.w200, color: Color(0xFF00FFC2))),
          ),
          const SizedBox(height: 8),
          const Text('S U D H A', style: TextStyle(letterSpacing: 6, color: Colors.white54)),
          const SizedBox(height: 35),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: TextField(
              controller: _urlController,
              onSubmitted: _loadUrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF161622),
                hintText: 'Search or enter stream URL...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopControl() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF14141E).withOpacity(0.92),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isMirrorMode ? "Mode: Screen Mirror" : "Mode: Web Sync (Anti-DRM)",
              style: TextStyle(fontSize: 11, color: isMirrorMode ? Colors.orangeAccent : const Color(0xFF00FFC2)),
            ),
          ),
          InkWell(
            onTap: () => setState(() => isMirrorMode = !isMirrorMode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isMirrorMode ? Colors.orangeAccent.withOpacity(0.2) : const Color(0xFF00FFC2).withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                isMirrorMode ? "Turn OFF Mirror" : "Turn ON Mirror",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isMirrorMode ? Colors.orangeAccent : const Color(0xFF00FFC2)),
              ),
            ),
          )
        ],
      ),
    );
  }

  void _openChatModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111118),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return SizedBox(
            height: 350,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Text("Sudha Room Chat", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
                const Divider(color: Colors.white10),
                Expanded(
                  child: ListView.builder(
                    itemCount: chatMessages.length,
                    itemBuilder: (context, index) {
                      final msg = chatMessages[index];
                      return ListTile(
                        dense: true,
                        title: Text(msg['sender'] ?? '', style: const TextStyle(color: Color(0xFF00FFC2), fontSize: 12)),
                        subtitle: Text(msg['message'] ?? '', style: const TextStyle(color: Colors.white)),
                      );
                    },
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(hintText: "Type message...", border: InputBorder.none),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Color(0xFF00FFC2)),
                      onPressed: () {
                        if (_chatController.text.isNotEmpty) {
                          socket.emit("send-chat", {"roomId": roomId, "sender": "Me", "message": _chatController.text});
                          _chatController.clear();
                          setModalState(() {});
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        });
      },
    );
  }
}
