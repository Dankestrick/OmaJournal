import QtQuick
import qs.Commons
import "Logo.js" as Logo

// Faint "OMAJOURNAL" in the font of Omarchy's logo, repeated in rows that run
// diagonally (top left to bottom right), in the theme's accent color. Put it
// first inside a surface so it sits behind everything.
Item {
  id: backdrop
  anchors.fill: parent
  clip: true

  property color color: Color.accent
  property string fontFamily: Style.font.family
  // How strong the pattern is.
  property real strength: 0.09
  // Width of one copy, as a share of the surface's width.
  property real copyWidth: 0.3

  readonly property int artColumns: Logo.LOGO.indexOf("\n")
  readonly property int artPixelSize: Math.max(4, Math.round(width * copyWidth / (artColumns * 0.6)))
  readonly property real diagonal: Math.sqrt(width * width + height * height)

  Item {
    id: tiles
    width: backdrop.diagonal * 1.2
    height: width
    anchors.centerIn: parent
    rotation: 45
    opacity: backdrop.strength
    // Fade the whole pattern as one image, not each copy separately.
    layer.enabled: true

    Column {
      anchors.centerIn: parent
      spacing: backdrop.artPixelSize * 5

      Repeater {
        model: Math.ceil(tiles.height / (backdrop.artPixelSize * 16)) + 1
        delegate: Row {
          required property int index
          spacing: backdrop.artPixelSize * 8
          // Every other row shifts half a copy, like bricks.
          x: index % 2 ? -(measure.width + spacing) / 2 : 0

          Repeater {
            model: Math.ceil(tiles.width / Math.max(1, measure.width)) + 2
            delegate: Text {
              textFormat: Text.PlainText
              text: Logo.LOGO
              color: backdrop.color
              font.family: backdrop.fontFamily
              font.pixelSize: backdrop.artPixelSize
              // Rows exactly one glyph tall, so the block characters touch.
              lineHeightMode: Text.FixedHeight
              lineHeight: metrics.height
            }
          }
        }
      }
    }
  }

  // Measures one copy for the spacing math above.
  Text {
    id: measure
    visible: false
    textFormat: Text.PlainText
    text: Logo.LOGO
    font.family: backdrop.fontFamily
    font.pixelSize: backdrop.artPixelSize
    lineHeightMode: Text.FixedHeight
    lineHeight: metrics.height
  }

  FontMetrics {
    id: metrics
    font.family: backdrop.fontFamily
    font.pixelSize: backdrop.artPixelSize
  }
}
