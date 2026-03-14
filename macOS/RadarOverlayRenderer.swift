//
//  RadarOverlayRenderer.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-09.
//

import ImageIO
import MapKit
import os

private let logger = Logger(
    subsystem: "io.fluxhaus.FluxHaus", category: "RadarOverlay"
)

/// Overlay covering the world for custom radar tile rendering.
class RadarAnimationOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    var boundingMapRect: MKMapRect { MKMapRect.world }

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

/// Custom renderer that draws radar tiles from an in-memory
/// cache. Frame changes use `setFrame()` → `setNeedsDisplay()`
/// which redraws from cache instantly — no overlay add/remove,
/// no reloadData(), no MapKit tile-cache involvement.
class RadarAnimationRenderer: MKOverlayRenderer, @unchecked Sendable {
    private let urlBuilder: TileURLBuilder
    private var _framePath: String?
    private var cache: [String: CGImage] = [:]
    private var pending: Set<String> = []
    private let lock = NSLock()

    init(
        overlay: MKOverlay,
        urlBuilder: @escaping TileURLBuilder,
        initialPath: String?,
        overlayAlpha: CGFloat = 0.7
    ) {
        self.urlBuilder = urlBuilder
        self._framePath = initialPath
        super.init(overlay: overlay)
        self.alpha = overlayAlpha
    }

    // MARK: - Public API

    func setFrame(_ path: String) {
        lock.lock()
        _framePath = path
        lock.unlock()
        setNeedsDisplay()
    }

    func preload(
        frames: [RadarFrame],
        visibleRect: MKMapRect,
        viewWidth: CGFloat
    ) {
        guard !frames.isEmpty,
              visibleRect.size.width > 0,
              viewWidth > 0 else { return }
        let scale = MKZoomScale(viewWidth / visibleRect.size.width)
        let zoomLvl = zoom(for: scale)
        let range = tileRange(for: visibleRect, zoom: zoomLvl)
        guard range.count > 0, range.count <= 50 else { return }
        for frame in frames {
            for col in range.minCol...range.maxCol {
                for row in range.minRow...range.maxRow {
                    fetchTile(
                        path: frame.path,
                        zoom: zoomLvl, col: col, row: row
                    )
                }
            }
        }
    }

    // MARK: - Drawing

    override func draw(
        _ mapRect: MKMapRect,
        zoomScale: MKZoomScale,
        in ctx: CGContext
    ) {
        lock.lock()
        let currentPath = _framePath
        lock.unlock()
        guard let currentPath else { return }

        let zoomLvl = zoom(for: zoomScale)
        let range = tileRange(for: mapRect, zoom: zoomLvl)
        guard !range.isEmpty else { return }

        for col in range.minCol...range.maxCol {
            for row in range.minRow...range.maxRow {
                let key = cacheKey(currentPath, zoomLvl, col, row)
                lock.lock()
                let image = cache[key]
                lock.unlock()
                if let image {
                    drawTile(image, col: col, row: row,
                             zoom: zoomLvl, in: ctx)
                } else {
                    fetchTile(
                        path: currentPath,
                        zoom: zoomLvl, col: col, row: row
                    )
                }
            }
        }
    }

    private func drawTile(
        _ image: CGImage, col: Int, row: Int,
        zoom: Int, in ctx: CGContext
    ) {
        let tRect = tileMapRect(col: col, row: row, zoom: zoom)
        let drawRect = rect(for: tRect)
        ctx.saveGState()
        // Flip: CGContext is y-up, map tiles are y-down
        ctx.translateBy(
            x: drawRect.minX,
            y: drawRect.minY + drawRect.height
        )
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(
            image,
            in: CGRect(origin: .zero, size: drawRect.size)
        )
        ctx.restoreGState()
    }

    // MARK: - Tile Fetching

    private func fetchTile(
        path: String, zoom: Int, col: Int, row: Int
    ) {
        let key = cacheKey(path, zoom, col, row)
        lock.lock()
        guard cache[key] == nil, !pending.contains(key) else {
            lock.unlock()
            return
        }
        pending.insert(key)
        lock.unlock()

        guard let url = urlBuilder(path, zoom, col, row) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data,
                  let src = CGImageSourceCreateWithData(
                      data as CFData, nil),
                  let img = CGImageSourceCreateImageAtIndex(
                      src, 0, nil)
            else { return }

            self.lock.lock()
            self.cache[key] = img
            self.pending.remove(key)
            self.lock.unlock()

            let tRect = self.tileMapRect(col: col, row: row, zoom: zoom)
            DispatchQueue.main.async {
                self.setNeedsDisplay(tRect)
            }
        }.resume()
    }

    // MARK: - Tile Math

    private func cacheKey(
        _ path: String, _ zoom: Int, _ col: Int, _ row: Int
    ) -> String {
        "\(path)/\(zoom)/\(col)/\(row)"
    }

    private func zoom(for scale: MKZoomScale) -> Int {
        // World = 2^28 map-pts; tile = 2^(28-z) map-pts
        // Want 256 = 2^(28-z) * scale  →  z = 20 + log2(scale)
        let level = 20 + Int(round(log2(Double(scale))))
        return min(max(level, 1), 10) // Rainbow.ai supports 0-12
    }

    private func tileRange(
        for rect: MKMapRect, zoom: Int
    ) -> TileRange {
        let count = Double(1 << zoom)
        let tileW = MKMapSize.world.width / count
        let tileH = MKMapSize.world.height / count
        return TileRange(
            minCol: max(0, Int(floor(rect.minX / tileW))),
            maxCol: min(
                Int(count) - 1,
                Int(floor((rect.maxX - 1) / tileW))),
            minRow: max(0, Int(floor(rect.minY / tileH))),
            maxRow: min(
                Int(count) - 1,
                Int(floor((rect.maxY - 1) / tileH)))
        )
    }

    private func tileMapRect(
        col: Int, row: Int, zoom: Int
    ) -> MKMapRect {
        let count = Double(1 << zoom)
        let tileW = MKMapSize.world.width / count
        let tileH = MKMapSize.world.height / count
        return MKMapRect(
            x: Double(col) * tileW, y: Double(row) * tileH,
            width: tileW, height: tileH
        )
    }
}

private struct TileRange {
    let minCol: Int
    let maxCol: Int
    let minRow: Int
    let maxRow: Int

    var isEmpty: Bool { maxCol < minCol || maxRow < minRow }
    var count: Int {
        guard !isEmpty else { return 0 }
        return (maxCol - minCol + 1) * (maxRow - minRow + 1)
    }
}
