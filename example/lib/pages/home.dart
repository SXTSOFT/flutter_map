import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/latlong/latlong.dart';

import '../widgets/drawer.dart';
import 'package:flutter/rendering.dart' as img;
import 'package:flutter/services.dart' as img;
import 'package:flutter/widgets.dart' as img;
import 'package:flutter/painting.dart' as img;
import 'dart:ui' as ui;

class HomePage extends StatelessWidget {
  static const String route = '/';

  Future<OverlayImage> _createOverlayImage(String a) {
    ImageProvider imageProvider = a.startsWith("http")
        ? NetworkImage(a)
        : a.startsWith("/") ? FileImage(File(a)) : AssetImage(a);
    return _loadImage(imageProvider).then((img) {
      OverlayImage overlayImage = OverlayImage(
        bounds: LatLngBounds(LatLng(0.0, 0.0), LatLng(-256.0, 256.0)),
        imageProvider: imageProvider,
      );
      overlayImage.image = img;
      return overlayImage;
    });
  }

  Future<ui.Image> _loadImage(img.ImageProvider imageProvider) async {
    var stream = imageProvider.resolve(img.ImageConfiguration.empty);
    var completer = Completer<ui.Image>();
    ImageStreamListener listenerStream;
    listenerStream =
        new ImageStreamListener((img.ImageInfo frame, bool synchronousCall) {
      var image = frame.image;
      completer.complete(image);
      stream.removeListener(listenerStream);
    });
    stream.addListener(listenerStream);
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    // var markers = <Marker>[
    //   Marker(
    //     width: 80.0,
    //     height: 80.0,
    //     point: LatLng(51.5, -0.09),
    //     builder: (ctx) => Container(
    //           child: FlutterLogo(),
    //         ),
    //   ),
    //   Marker(
    //     width: 80.0,
    //     height: 80.0,
    //     point: LatLng(53.3498, -6.2603),
    //     builder: (ctx) => Container(
    //           child: FlutterLogo(
    //             colors: Colors.green,
    //           ),
    //         ),
    //   ),
    //   Marker(
    //     width: 80.0,
    //     height: 80.0,
    //     point: LatLng(48.8566, 2.3522),
    //     builder: (ctx) => Container(
    //           child: FlutterLogo(colors: Colors.purple),
    //         ),
    //   ),
    // ];
    return Scaffold(
      appBar: AppBar(title: Text('Home')),
      drawer: buildDrawer(context, route),
      body: Padding(
        padding: EdgeInsets.all(8.0),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.only(top: 8.0, bottom: 8.0),
              child: Text('This is a map that is showing (51.5, -0.9).'),
            ),
            Flexible(
              // child: FlutterMap(
              //   options: MapOptions(
              //       zoom: 8,
              //       onTap: (LatLng point) {},
              //       onLongPress: (LatLng point) {},
              //       onPositionChanged: (MapPosition position, bool hasGesture,
              //           bool isUserGesture) {}),
              //   layers: [
              //     TileLayerOptions(
              //       subdomains: ['1', '2', '3'],
              //       urlTemplate:
              //           "http://mt{s}.google.cn/vt/lyrs=r&hl=zh-CN&gl=cn&x={x}&y={y}&z={z}",
              //     ),
              //   ],
              // ),
              child: FlutterMap(
                options: MapOptions(
                    crs: RicentCrs(),
                    center: LatLng(-128, 128),
                    zoom: 0.5,
                    maxZoom: 3,
                    swPanBoundary: LatLng(-256, 0),
                    nePanBoundary: LatLng(0, 256)),
                layers: [
                  TileLayerOptions(
                      urlTemplate:
                          'http://yz.chinadydc.com/api/v2/files/104128b1-aa28-4429-ae26-f02d5a132fd6/content/tile/{x}/{y}/{z}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
