import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Commons
import "../Model.js" as Model

// The words to whatever is playing, following the song.
//
// The player comes from MPRIS through the same judgement the music card uses:
// pickPlayerIndex follows whatever is actually playing, or the player a
// `player` setting names. The lyrics themselves are fetched by the service
// from LRCLIB and cached per track, so this file never talks to the network
// and never holds a key.
//
// When the track has synced (timestamped) lyrics, the current line is found by
// binary search against the player's position and the card slides through the
// song exactly as fast as the song does. Pausing the track pauses the card,
// because the position stops moving; seeking jumps the highlighted line to
// where the seek landed. Songs without timestamps fall back to plain wording
// spread evenly across the track's length, or simply shown when the player
// has not said how long it is.
//
// The three animation modes are how a line gives way to the next:
//
//   fade        old line fades out as the new one fades in
//   slide       the new line slides in from the side as the old one leaves
//   typewriter  the current line types itself, character by character
//
// The house rules say a wallpaper does not move -- the editor is where motion
// belongs. This card is the deliberate exception: following the song *is* the
// point of a lyric widget, so the display animates exactly when the words
// change and stays perfectly still the rest of the time. The mode and its
// speed are settings, scaled down to a setting only when it is on.

Item {
  id: root

  // Injected by Surface.qml.
  property var service: null
  property var instance: null
  property var card: null
  readonly property var settings: instance && instance.settings ? instance.settings : ({})

  readonly property color foreground: Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Util.alpha(Color.foreground, 0.55)
  readonly property string fontFamily: settings.fontFamily
    ? String(settings.fontFamily) : Style.font.family

  // Every size derives from a cell, not the card: a [2, 2] card gave
  // Math.min(width, height) double the type it should have, and what a second
  // row is for is more words, not bigger ones.
  readonly property int spanCols: instance && instance.cols > 0 ? instance.cols : 1
  readonly property int spanRows: instance && instance.rows > 0 ? instance.rows : 1
  readonly property real unit: Math.min(width / spanCols, height / spanRows)
  readonly property real pad: Math.round(unit * 0.08)

  // ------------------------------------------------------------ settings

  // Blank follows whatever is playing, like the music card.
  readonly property string preferredPlayer: String(settings.player || "")

  readonly property bool wrapText: settings.wrap !== false
  readonly property string animationMode: String(settings.animationMode || "fade")
  readonly property string align: String(settings.alignment || "center")

  readonly property real textAlpha: {
    var n = Number(settings.textOpacity)
    return isFinite(n) ? Math.max(0.1, Math.min(1, n)) : 0.95
  }
  readonly property real posX: {
    var n = Number(settings.posX)
    return isFinite(n) ? Math.max(-4000, Math.min(4000, n)) : 0
  }
  readonly property real posY: {
    var n = Number(settings.posY)
    return isFinite(n) ? Math.max(-4000, Math.min(4000, n)) : 0
  }
  // 0 means "size it to the card", which is the house way.
  readonly property real textSize: {
    var n = Number(settings.fontSize)
    if (!isFinite(n) || n < 6) return Math.max(10, Math.round(root.unit * 0.075))
    return Math.max(6, Math.min(400, n))
  }
  readonly property real textWidth: {
    var n = Number(settings.maxWidth)
    var fit = Math.max(24, root.width - root.pad * 2)
    if (!isFinite(n) || n <= 0) return fit
    return Math.max(24, Math.min(n, fit))
  }
  readonly property real animSpeed: {
    var n = Number(settings.animationSpeed)
    return isFinite(n) ? Math.max(0.1, Math.min(10, n)) : 1
  }
  readonly property int context: {
    var n = Number(settings.contextLines)
    return isFinite(n) ? Math.max(0, Math.min(12, Math.round(n))) : 2
  }

  // How long a line takes to give way. In typewriter mode the words type one
  // by one instead, so the fade that swaps lines is kept short.
  readonly property int animDuration: Math.max(1, Math.round(300 / root.animSpeed))
  readonly property int typeInterval: Math.max(1, Math.round(45 / root.animSpeed))
  readonly property int lineAnimDuration: root.animationMode === "typewriter"
    ? Math.max(1, Math.round(root.animDuration * 0.35)) : root.animDuration

  readonly property real slideOffset: Math.round(root.unit * 0.12)
  readonly property real lineGap: Math.round(root.unit * 0.045)
  readonly property real headerSize: Math.max(8, Math.round(root.unit * 0.06))

  // ------------------------------------------------------------ the player

  readonly property var players: Mpris.players ? Mpris.players.values : null
  readonly property int index: Model.pickPlayerIndex(players, root.preferredPlayer)
  readonly property var player: players && index >= 0 && index < players.length
    ? players[index] : null

  readonly property bool hasPlayer: player !== null
  readonly property string title: hasPlayer ? String(player.trackTitle || "") : ""
  readonly property string artist: hasPlayer ? String(player.trackArtist || "") : ""
  readonly property bool playing: hasPlayer && player.isPlaying === true
  readonly property real position: hasPlayer && player.positionSupported ? player.position : 0
  readonly property real length: hasPlayer && player.lengthSupported ? player.length : 0

  // A title or an artist is enough to say something is playing; a lyric lookup
  // wants both though, and the service waits out the moment when only one has
  // arrived.
  readonly property bool ready: Model.hasPlayable(player)
  readonly property string trackKey: Model.trackKey(artist, title)

  // ----------------------------------------------------------- the lyrics

  readonly property var lyricData: service && service.lyrics && root.trackKey
    ? service.lyrics[root.trackKey] : null
  readonly property bool pending: ready && !lyricData
  readonly property bool fetching: !!lyricData && lyricData.state === "fetching"
  readonly property bool missing: !!lyricData && lyricData.state === "missing"
  readonly property var lines: lyricData && lyricData.state === "ready"
    && Array.isArray(lyricData.lines) ? lyricData.lines : []
  readonly property bool synced: !!lyricData && lyricData.synced === true
  readonly property bool hasLines: lines.length > 0

  // The line the song is at. Synced lyrics answer from their timestamps; plain
  // lyrics can only estimate, spreading evenly across the track, and a player
  // without a length gets -1, meaning "just show the words".
  readonly property int currentIndex: root.synced
    ? Model.lyricIndexAt(lines, position)
    : Model.estimatedIndex(lines, position, root.length)

  // The window of lines shown around the current one, clamped so the window
  // never raises a gap at the top or bottom of a short lyric.
  readonly property int showPerSide: root.context
  readonly property int currentOrFirst: root.currentIndex === -1 ? 0 : root.currentIndex
  readonly property int maxFirst: Math.max(0, lines.length - (showPerSide * 2 + 1))
  readonly property int firstVisible: Math.max(0, Math.min(currentOrFirst - showPerSide, maxFirst))
  readonly property int visibleCount: Math.min(lines.length - firstVisible, showPerSide * 2 + 1)
  readonly property int visibleCurrent: root.currentIndex === -1 ? -1 : root.currentIndex - root.firstVisible
  readonly property bool hasCurrent: root.visibleCurrent !== -1
  readonly property var visibleLines:
    lines.slice(firstVisible, firstVisible + visibleCount)

  // The position only ticks while something is playing, and only while there
  // is a song to time against.
  readonly property bool progresses: root.playing && root.hasLines
    && lyricData && lyricData.state === "ready"
    && (root.synced || root.length > 0)

  FrameAnimation {
    running: root.progresses
    onTriggered: if (root.player) root.player.positionChanged()
  }

  // Ask for the words the moment the song changes. The service discards
  // repeated asks for a track it already has, so this is cheap to call often.
  function askForLyrics() {
    if (!service || !root.trackKey) return
    service.requestLyrics(root.artist, root.title, root.length)
  }
  onTrackKeyChanged: root.askForLyrics()
  Component.onCompleted: root.askForLyrics()

  // --------------------------------------------------------------- states

  readonly property string stateMessage: {
    if (!root.ready) return "Nothing playing"
    if (root.missing) return "No lyrics found"
    if (root.pending && service && service.lyricsError) return "Lyrics unavailable"
    return "Retrieving lyrics\u2026"
  }
  readonly property bool showState: root.ready && !root.hasLines

  // What is playing, small, above the words: the label a lyric card needs to
  // say which song these belong to.
  readonly property string header: root.title + (root.artist ? " \u2014 " + root.artist : "")

  // ---------------------------------------------------------------- paint

  Text {
    id: stateText
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: root.posX
    anchors.verticalCenterOffset: root.posY
    visible: root.showState
    width: Math.max(0, root.textWidth)
    horizontalAlignment: root.alignment()
    text: root.stateMessage
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: root.textSize
    renderType: Text.NativeRendering
  }

  Column {
    id: linesBlock
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: root.posX
    anchors.verticalCenterOffset: root.posY
    width: Math.min(parent.width, root.textWidth + root.pad * 2)
    spacing: root.lineGap
    visible: root.hasLines

    // The song these words belong to, and the one accent on the card. It is
    // the only thing the words themselves cannot say.
    Text {
      visible: root.header !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.header
      textFormat: Text.PlainText
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: root.headerSize
      font.letterSpacing: Math.round(root.unit * 0.075) * 0.12
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }

    Repeater {
      model: root.visibleLines

      delegate: Item {
        id: line
        required property var modelData
        required property int index

        readonly property string full: Model.lineText(modelData)
        readonly property bool isCurrentLine: root.visibleCurrent === index
        readonly property bool isPast: index < root.visibleCurrent
        readonly property real lineWidth: Math.max(0, linesBlock.width - root.pad * 2)

        width: line.lineWidth
        height: lineText.implicitHeight

        // The current line is the only one at full strength; the words ahead
        // are fainter still than the ones behind, so the eye lands where the
        // song is. With no line current (before the first timestamp, or no
        // timestamps at all) everything simply shows.
        readonly property real targetOpacity: !root.hasCurrent ? root.textAlpha
          : (isCurrentLine ? root.textAlpha
            : (isPast ? root.textAlpha * 0.5 : root.textAlpha * 0.32))

        readonly property real targetX: root.hasCurrent && root.animationMode === "slide"
          ? (isCurrentLine ? 0 : (isPast ? -root.slideOffset : root.slideOffset))
          : 0

        // How much of the word has appeared. Managed by the typewriter below;
        // anything but the current line shows in full whatever it holds.
        property int typed: 0

        // Letters appear one by one. Playback drives it: a paused track freezes
        // a half-typed line, and seeking lands on a line already complete.
        Timer {
          id: typeTimer
          interval: root.typeInterval
          repeat: true
          running: line.isCurrentLine && root.animationMode === "typewriter" && root.playing
          onTriggered: {
            if (line.typed < line.full.length) line.typed += 1
            else stop()
          }
        }

        // A line that arrives while the song is playing types itself from the
        // top. One that arrives paused or as the result of a seek has no
        // honest halfway point, so it is shown complete.
        function resetTyping() {
          if (!line.isCurrentLine) { typeTimer.stop(); return }
          if (root.playing) { line.typed = 0; typeTimer.restart() }
          else { line.typed = line.full.length; typeTimer.stop() }
        }

        onIsCurrentLineChanged: resetTyping()
        // A Repeater handed a new list recycles its delegates: the old line's
        // half-typed state must not leak onto the new words.
        onFullChanged: resetTyping()
        Component.onCompleted: resetTyping()

        Text {
          id: lineText
          x: line.targetX
          width: line.lineWidth
          text: root.animationMode === "typewriter" && line.isCurrentLine
            ? line.full.slice(0, line.typed) : line.full
          textFormat: Text.PlainText
          horizontalAlignment: root.alignment()
          wrapMode: root.wrapText ? Text.Wrap : Text.NoWrap
          elide: root.wrapText ? Text.ElideNone : Text.ElideRight
          color: root.foreground
          opacity: line.targetOpacity
          font.family: root.fontFamily
          font.pixelSize: root.textSize
          font.weight: line.isCurrentLine ? Font.Medium : Font.Normal
          renderType: Text.NativeRendering

          Behavior on opacity {
            NumberAnimation { duration: root.lineAnimDuration }
          }
          Behavior on x {
            NumberAnimation { duration: root.lineAnimDuration }
          }
        }
      }
    }
  }

  // The single accent on the card belongs to the song header; everything else
  // is foreground. Mirrors the rest of the set: one deliberate detail.
  function alignment() {
    if (root.align === "left") return Text.AlignLeft
    if (root.align === "right") return Text.AlignRight
    return Text.AlignHCenter
  }
}