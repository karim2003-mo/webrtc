import 'package:flutter/material.dart';
import 'package:websocket/testscreen.dart';

class Control extends StatelessWidget {
  Control({super.key});
  final TextEditingController roomidController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Control Screen'),
      ),
      body: Center(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: (){showDialog(context: context, builder: (context)=>Material(
                  child: Container(
                    width: MediaQuery.of(context).size.width *0.7,
                    height: MediaQuery.of(context).size.height *0.5,
                    padding: EdgeInsets.all(10),
                    color: Colors.white ,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextField(
                          controller: roomidController,
                          decoration: InputDecoration(
                            labelText: 'Enter Room ID',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        SizedBox(height: 20),
                        ElevatedButton(onPressed: (){Navigator.of(context).push(
                          MaterialPageRoute(builder: (context)=>VideoCallScreen(roomId: roomidController.text, isCaller: true))
                        );}, child: Text('Start')),
                      ],
                    ),
                  ),
                ));}, child: Text('Start Call'))),
                Expanded(child: ElevatedButton(onPressed: (){
                  showDialog(context: context, builder: (context)=>Material(
                    child: Container(
                      width: MediaQuery.of(context).size.width *0.7,
                      height: MediaQuery.of(context).size.height *0.5,
                      padding: EdgeInsets.all(10),
                      color: Colors.white ,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextField(
                            controller: roomidController,
                            decoration: InputDecoration(
                              labelText: 'Enter Room ID',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          SizedBox(height: 20),
                          ElevatedButton(onPressed: (){Navigator.of(context).push(
                            MaterialPageRoute(builder: (context)=>VideoCallScreen(roomId: roomidController.text, isCaller: false))
                          );}, child: Text('join')),
                        ],
                      ),
                    ),
                  ));
                }, child: Text('join Call'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}