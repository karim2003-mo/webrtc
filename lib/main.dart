import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:websocket/videoCall.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomePage(), // ✅ Use a proper child here
    );
  }
}

class HomePage extends StatelessWidget {
  HomePage({super.key});

  final TextEditingController roomIdController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Call App'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: roomIdController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Room ID',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    final roomId = roomIdController.text;
                    if (roomId.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VideoCallScreen(roomId: roomId,isHost: false,),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid Room ID')),
                      );
                    }
                  },
                  child: const Text('Join Room'),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoCallScreen(isHost: true,), // assuming roomId is optional
                      ),
                    );
                  },
                  child: const Text('Create Room'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
