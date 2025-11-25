import 'package:flutter/material.dart';
import 'package:passport_scanner/passport_scanner.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Passport Scanner Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String text = 'Scan result will be shown here';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('Passport Scanner Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => Scaffold(
                      appBar: AppBar(title: Text('Passport Scanner')),
                      body: PassportScannerWidget(
                        onScanned: (result) {
                          setState(() {
                            text =
                                'Scanned: ${result.documentNumber}, ${result.givenNames} ${result.surnames}';
                          });
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ),
                );
              },
              child: Text('Scan'),
            ),
            Text(text),
          ],
        ),
      ),
    );
  }
}
