import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_map/latlong/latlong.dart';
import 'package:tuple/tuple.dart';
import 'package:flutter_map/src/core/util.dart' as util;

import '../../flutter_map.dart';
import '../../plugin_api.dart';

class BigImageLayerOptions extends LayerOptions {
  final ui.Image image;

  final bool tms;

  final double tileSize;

  final double maxZoom;

  final bool zoomReverse;
  final double zoomOffset;

  ///Color shown behind the tiles.
  final Color backgroundColor;

  /// When panning the map, keep this many rows and columns of tiles before
  /// unloading them.
  final int keepBuffer;
  ImageProvider placeholderImage;
  Map<String, String> additionalOptions;

  BigImageLayerOptions(
      {this.image,
      this.tileSize = 256.0,
      this.maxZoom = 18.0,
      this.zoomReverse = false,
      this.zoomOffset = 0.0,
      this.additionalOptions = const <String, String>{},
      this.keepBuffer = 2,
      this.backgroundColor = const Color(0xFFFFFFFF),
      this.placeholderImage,
      this.tms = false,
      rebuild})
      : super(rebuild: rebuild);
}

class BigImageLayer extends StatefulWidget {
  final BigImageLayerOptions options;
  final MapState mapState;
  final Stream<Null> stream;

  BigImageLayer({
    this.options,
    this.mapState,
    this.stream,
  });

  @override
  State<StatefulWidget> createState() {
    return _BigImageLayerState();
  }
}

class _BigImageLayerState extends State<BigImageLayer> {
  MapState get map => widget.mapState;

  BigImageLayerOptions get options => widget.options;
  Bounds _globalTileRange;
  Tuple2<double, double> _wrapX;
  Tuple2<double, double> _wrapY;
  double _tileZoom;
  Level _level;
  StreamSubscription _moveSub;

  final Map<String, Tile> _tiles = {};
  final Map<double, Level> _levels = {};
  final Paint _paint = Paint();

  @override
  void initState() {
    super.initState();
    _resetView();
    _moveSub = widget.stream.listen((_) => _handleMove());
  }

  @override
  void dispose() {
    super.dispose();
    _moveSub?.cancel();
    options.image.dispose();
  }

  void _handleMove() {
    setState(() {
      _pruneTiles();
      _resetView();
    });
  }

  void _resetView() {
    _setView(map.center, map.zoom);
  }

  void _setView(LatLng center, double zoom) {
    var tileZoom = _clampZoom(zoom.round().toDouble());
    if (_tileZoom != tileZoom) {
      _tileZoom = tileZoom;
      _updateLevels();
      _resetGrid();
    }
    _setZoomTransforms(center, zoom);
  }

  Level _updateLevels() {
    var zoom = _tileZoom;
    var maxZoom = options.maxZoom;

    if (zoom == null) return null;

    var toRemove = <double>[];
    for (var z in _levels.keys) {
      if (_levels[z].children.isNotEmpty || z == zoom) {
        _levels[z].zIndex = maxZoom = (zoom - z).abs();
      } else {
        toRemove.add(z);
      }
    }

    for (var z in toRemove) {
      _removeTilesAtZoom(z);
    }

    var level = _levels[zoom];
    var map = this.map;

    if (level == null) {
      level = _levels[zoom] = Level();
      level.zIndex = maxZoom;
      var newOrigin = map.project(map.unproject(map.getPixelOrigin()), zoom);
      if (newOrigin != null) {
        level.origin = newOrigin;
      } else {
        level.origin = CustomPoint(0.0, 0.0);
      }
      level.zoom = zoom;

      _setZoomTransform(level, map.center, map.zoom);
    }
    _level = level;
    return level;
  }

  void _pruneTiles() {
    var center = map.center;
    var pixelBounds = _getTiledPixelBounds(center);
    var tileRange = _pxBoundsToTileRange(pixelBounds);
    var margin = options.keepBuffer ?? 2;
    var noPruneRange = Bounds(
        tileRange.bottomLeft - CustomPoint(margin, -margin),
        tileRange.topRight + CustomPoint(margin, -margin));
    for (var tileKey in _tiles.keys) {
      var tile = _tiles[tileKey];
      var c = tile.coords;
      if (c.z != _tileZoom || !noPruneRange.contains(CustomPoint(c.x, c.y))) {
        tile.current = false;
      }
    }
    _tiles.removeWhere((s, tile) => tile.current == false);
  }

  void _setZoomTransform(Level level, LatLng center, double zoom) {
    var scale = map.getZoomScale(zoom, level.zoom);
    var pixelOrigin = map.getNewPixelOrigin(center, zoom).round();
    if (level.origin == null) {
      return;
    }
    var translate = level.origin.multiplyBy(scale) - pixelOrigin;
    level.translatePoint = translate;
    level.scale = scale;
  }

  void _setZoomTransforms(LatLng center, double zoom) {
    for (var i in _levels.keys) {
      _setZoomTransform(_levels[i], center, zoom);
    }
  }

  void _removeTilesAtZoom(double zoom) {
    var toRemove = <String>[];
    for (var key in _tiles.keys) {
      if (_tiles[key].coords.z != zoom) {
        continue;
      }
      toRemove.add(key);
    }
    for (var key in toRemove) {
      _removeTile(key);
    }
  }

  void _removeTile(String key) {
    var tile = _tiles[key];
    if (tile == null) {
      return;
    }
    _tiles[key].current = false;
  }

  void _resetGrid() {
    var map = this.map;
    var crs = map.options.crs;
    var tileSize = getTileSize();
    var tileZoom = _tileZoom;

    var bounds = map.getPixelWorldBounds(_tileZoom);
    if (bounds != null) {
      _globalTileRange = _pxBoundsToTileRange(bounds);
    }

    // wrapping
    _wrapX = crs.wrapLng;
    if (_wrapX != null) {
      var first =
          (map.project(LatLng(0.0, crs.wrapLng.item1), tileZoom).x / tileSize.x)
              .floor()
              .toDouble();
      var second =
          (map.project(LatLng(0.0, crs.wrapLng.item2), tileZoom).x / tileSize.y)
              .ceil()
              .toDouble();
      _wrapX = Tuple2(first, second);
    }

    _wrapY = crs.wrapLat;
    if (_wrapY != null) {
      var first =
          (map.project(LatLng(crs.wrapLat.item1, 0.0), tileZoom).y / tileSize.x)
              .floor()
              .toDouble();
      var second =
          (map.project(LatLng(crs.wrapLat.item2, 0.0), tileZoom).y / tileSize.y)
              .ceil()
              .toDouble();
      _wrapY = Tuple2(first, second);
    }
  }

  double _clampZoom(double zoom) {
    // todo
    return zoom;
  }

  CustomPoint getTileSize() {
    return CustomPoint(options.tileSize, options.tileSize);
  }

  @override
  Widget build(BuildContext context) {
    var pixelBounds = _getTiledPixelBounds(map.center);
    var tileRange = _pxBoundsToTileRange(pixelBounds);
    var tileCenter = tileRange.getCenter();
    var queue = <Coords>[];

    // mark tiles as out of view...
    for (var key in _tiles.keys) {
      var c = _tiles[key].coords;
      if (c.z != _tileZoom) {
        _tiles[key].current = false;
      }
    }

    _setView(map.center, map.zoom);

    for (var j = tileRange.min.y; j <= tileRange.max.y; j++) {
      for (var i = tileRange.min.x; i <= tileRange.max.x; i++) {
        var coords = Coords(i.toDouble(), j.toDouble());
        coords.z = _tileZoom;

        if (!_isValidTile(coords)) {
          continue;
        }

        // Add all valid tiles to the queue on Flutter
        queue.add(coords);
      }
    }

    if (queue.isNotEmpty) {
      for (var i = 0; i < queue.length; i++) {
        _tiles[_tileCoordsToKey(queue[i])] = Tile(_wrapCoords(queue[i]), true);
      }
    }

    var tilesToRender = <Tile>[];
    for (var tile in _tiles.values) {
      if ((tile.coords.z - _level.zoom).abs() > 1) {
        continue;
      }
      tilesToRender.add(tile);
    }
    tilesToRender.sort((aTile, bTile) {
      Coords<double> a = aTile.coords;
      Coords<double> b = bTile.coords;
      // a = 13, b = 12, b is less than a, the result should be positive.
      if (a.z != b.z) {
        return (b.z - a.z).toInt();
      }
      return (a.distanceTo(tileCenter) - b.distanceTo(tileCenter)).toInt();
    });

    var tileWidgets = <Widget>[];
    for (var tile in tilesToRender) {
      tileWidgets.add(_createTileWidget(tile.coords));
    }

    return Container(
      child: Stack(
        children: tileWidgets,
      ),
      color: options.backgroundColor,
    );
  }

  Bounds _getTiledPixelBounds(LatLng center) {
    return map.getPixelBounds(_tileZoom);
  }

  Bounds _pxBoundsToTileRange(Bounds bounds) {
    var tileSize = getTileSize();
    return Bounds(
      bounds.min.unscaleBy(tileSize).floor(),
      bounds.max.unscaleBy(tileSize).ceil() - CustomPoint(1, 1),
    );
  }

  bool _isValidTile(Coords coords) {
    var crs = map.options.crs;
    if (!crs.infinite) {
      var bounds = _globalTileRange;
      if ((crs.wrapLng == null &&
              (coords.x < bounds.min.x || coords.x > bounds.max.x)) ||
          (crs.wrapLat == null &&
              (coords.y < bounds.min.y || coords.y > bounds.max.y))) {
        return false;
      }
    }
    return true;
  }

  String _tileCoordsToKey(Coords coords) {
    return '${coords.x}:${coords.y}:${coords.z}';
  }

  Widget _createTileWidget(Coords coords) {
    var tilePos = _getTilePos(coords);
    var level = _levels[coords.z];
    var tileSize = getTileSize();
    var pos = (tilePos).multiplyBy(level.scale) + level.translatePoint;
    var width = tileSize.x * level.scale;
    var height = tileSize.y * level.scale;

    var zoom = coords.z;
    var size = tileSize.x;
    var x = coords.x, y = coords.y;

    var max = size * math.pow(2, zoom), maxTile = math.pow(2, zoom);
    var _w = widget.options.image.width, _h = widget.options.image.height;
    var _s = math.max(_w, _h) / max,
        _size = size * _s,
        _x = x * (size * _s),
        _y = y * (size * _s);
    Widget content;
    print(
        'coords x:${coords.x}, y:${coords.y}, z:${coords.z}, maxTile:$maxTile');
    if (x < 0 || y < 0 || x > maxTile || y > maxTile) {
      content = SizedBox(
        width: 256,
        height: 256,
        // decoration: BoxDecoration(color: Colors.green),
        child: Center(
          child: Text(
              'x:${coords.x}, y:${coords.y}, z:${coords.z}, maxTile:$maxTile'),
        ),
      );
    } else {
      var swidth = _x + _size > _w ? _w - _x : _size,
          sheight = _y + _size > _h ? _h - _y : _size,
          _width = (size * swidth) / _size,
          _height = (size * sheight) / _size;

      content = Container(
        child: CustomPaint(
          key: Key(_tileCoordsToKey(coords)),
          painter: _ImageTilePainter(
            image: widget.options.image,
            src: Rect.fromLTWH(_x, _y, swidth, sheight),
            dst: Rect.fromLTWH(0, 0, _width, _height),
            p: _paint,
          ),
        ),
      );
    }

    return Positioned(
        left: pos.x.toDouble(),
        top: pos.y.toDouble(),
        width: width.toDouble(),
        height: height.toDouble(),
        child: content);
  }

  Coords _wrapCoords(Coords coords) {
    var newCoords = Coords(
      _wrapX != null
          ? util.wrapNum(coords.x.toDouble(), _wrapX)
          : coords.x.toDouble(),
      _wrapY != null
          ? util.wrapNum(coords.y.toDouble(), _wrapY)
          : coords.y.toDouble(),
    );
    newCoords.z = coords.z.toDouble();
    return newCoords;
  }

  CustomPoint _getTilePos(Coords coords) {
    var level = _levels[coords.z];
    return coords.scaleBy(getTileSize()) - level.origin;
  }
}

class _ImageTilePainter extends CustomPainter {
  _ImageTilePainter({
    this.image,
    this.src,
    this.dst,
    this.p,
  });

  final ui.Image image;
  final Rect src;
  final Rect dst;
  final Paint p;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(image, src, dst, p);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
