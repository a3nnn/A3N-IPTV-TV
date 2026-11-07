package com.a3n.exo;

import android.app.Activity;
import android.content.Context;
import android.view.WindowManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.ColorInfo;
import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.TrackGroup;
import androidx.media3.common.TrackSelectionOverride;
import androidx.media3.common.TrackSelectionParameters;
import androidx.media3.common.Tracks;
import androidx.media3.common.VideoSize;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import androidx.media3.extractor.DefaultExtractorsFactory;
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory;
import androidx.media3.ui.AspectRatioFrameLayout;
import androidx.media3.ui.CaptionStyleCompat;
import androidx.media3.ui.PlayerView;
import androidx.media3.ui.SubtitleView;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

/**
 * The A3N IPTV player on Android TV: one Media3 ExoPlayer for the whole app,
 * drawn on a real Android video surface (the TV's video chip straight to the
 * screen), with audio / subtitle tracks and the video's frame rate.
 *
 * Dart side: package a3n_exo (MethodChannel "a3n_exo", events "a3n_exo/events",
 * view "a3n_exo/view").
 */
@OptIn(markerClass = UnstableApi.class)
public class A3nExoPlugin implements FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
  private Context context;
  private MethodChannel methods;
  private EventChannel events;
  @Nullable private EventChannel.EventSink sink;
  private final Handler main = new Handler(Looper.getMainLooper());

  @Nullable private ExoPlayer player;
  @Nullable private DefaultTrackSelector selector;
  private final List<PlayerView> views = new ArrayList<>();
  @Nullable private Activity activity;
  private boolean awake = false;

  // Subtitle look (from the app's settings).
  private int subColor = Color.WHITE;
  private float subScale = 1f;
  private boolean subBackground = false;
  private float subBgOpacity = 0.5f;

  private String lastError = null;

  private final Runnable ticker = new Runnable() {
    @Override public void run() {
      sendState();
      main.postDelayed(this, 500);
    }
  };

  // ------------------------------------------------------------ plugin

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding b) {
    context = b.getApplicationContext();
    methods = new MethodChannel(b.getBinaryMessenger(), "a3n_exo");
    methods.setMethodCallHandler(this);
    events = new EventChannel(b.getBinaryMessenger(), "a3n_exo/events");
    events.setStreamHandler(this);
    b.getPlatformViewRegistry().registerViewFactory("a3n_exo/view", new ViewFactory());
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding b) {
    methods.setMethodCallHandler(null);
    events.setStreamHandler(null);
    main.removeCallbacks(ticker);
    release();
  }

  @Override public void onListen(Object args, EventChannel.EventSink s) {
    sink = s;
    main.removeCallbacks(ticker);
    main.post(ticker);
  }

  @Override public void onCancel(Object args) {
    sink = null;
    main.removeCallbacks(ticker);
  }

  // ------------------------------------------------------------ player

  private ExoPlayer ensurePlayer() {
    if (player != null) return player;
    DefaultRenderersFactory renderers = new DefaultRenderersFactory(context)
        .setEnableDecoderFallback(true); // another decoder if the first one fails
    selector = new DefaultTrackSelector(context);
    // Live TV: start fast, keep a reasonable buffer.
    DefaultLoadControl load = new DefaultLoadControl.Builder()
        .setBufferDurationsMs(15000, 50000, 1500, 3000)
        .build();
    player = new ExoPlayer.Builder(context, renderers)
        .setTrackSelector(selector)
        .setLoadControl(load)
        .build();
    player.setAudioAttributes(new AudioAttributes.Builder()
        .setUsage(C.USAGE_MEDIA)
        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
        .build(), true);
    player.setVideoScalingMode(C.VIDEO_SCALING_MODE_SCALE_TO_FIT);
    player.addListener(new Player.Listener() {
      @Override public void onPlaybackStateChanged(int state) { sendState(); }
      @Override public void onIsPlayingChanged(boolean playing) {
        keepAwake(playing);
        sendState();
      }
      @Override public void onVideoSizeChanged(@NonNull VideoSize size) { sendState(); }
      @Override public void onTracksChanged(@NonNull Tracks tracks) {
        Map<String, Object> m = new HashMap<>();
        m.put("event", "tracks");
        send(m);
        sendState();
      }
      @Override public void onPlayerError(@NonNull PlaybackException error) {
        lastError = error.getErrorCodeName() + ": " + (error.getMessage() == null ? "" : error.getMessage());
        Map<String, Object> m = new HashMap<>();
        m.put("event", "error");
        m.put("code", error.getErrorCodeName());
        m.put("message", lastError);
        // Decoder / format problems: the app may try its other player.
        int c = error.errorCode;
        m.put("decoder", (c >= 4000 && c < 5000) || c == PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED);
        send(m);
        sendState();
      }
    });
    for (PlayerView v : views) v.setPlayer(player);
    return player;
  }

  private void open(String url, String userAgent, long startMs) {
    ExoPlayer p = ensurePlayer();
    lastError = null;
    DefaultHttpDataSource.Factory http = new DefaultHttpDataSource.Factory()
        .setUserAgent(userAgent)
        .setAllowCrossProtocolRedirects(true)
        .setConnectTimeoutMs(15000)
        .setReadTimeoutMs(20000);
    // IPTV .ts streams: start on any key frame, find the access units even
    // when the stream doesn't mark them.
    DefaultExtractorsFactory extractors = new DefaultExtractorsFactory()
        .setTsExtractorFlags(DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES
            | DefaultTsPayloadReaderFactory.FLAG_DETECT_ACCESS_UNITS);
    DefaultMediaSourceFactory sources = new DefaultMediaSourceFactory(http, extractors);
    MediaItem.Builder item = new MediaItem.Builder().setUri(url);
    String lower = url.toLowerCase();
    if (lower.contains(".m3u8")) item.setMimeType(MimeTypes.APPLICATION_M3U8);
    p.setMediaSource(sources.createMediaSource(item.build()), startMs > 0 ? startMs : C.TIME_UNSET);
    p.prepare();
    p.setPlayWhenReady(true);
  }

  /// While a video plays the TV must not start its screensaver (paused or
  /// stopped: the TV's normal screensaver time applies again).
  private void keepAwake(boolean on) {
    awake = on;
    if (activity != null) {
      if (on) activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
      else activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }
    for (PlayerView v : views) v.setKeepScreenOn(on);
  }

  @Override public void onAttachedToActivity(@NonNull ActivityPluginBinding b) {
    activity = b.getActivity();
    keepAwake(awake);
  }
  @Override public void onDetachedFromActivityForConfigChanges() { activity = null; }
  @Override public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding b) {
    activity = b.getActivity();
    keepAwake(awake);
  }
  @Override public void onDetachedFromActivity() {
    if (activity != null) activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    activity = null;
  }

  private void release() {
    keepAwake(false);
    for (PlayerView v : views) v.setPlayer(null);
    if (player != null) {
      player.release();
      player = null;
    }
  }

  private void setLanguages(List<String> audio, List<String> text, boolean textOff) {
    ensurePlayer();
    if (selector == null) return;
    TrackSelectionParameters.Builder b = selector.getParameters().buildUpon()
        .setPreferredAudioLanguages(audio.toArray(new String[0]))
        .setPreferredTextLanguages(text.toArray(new String[0]))
        .setSelectUndeterminedTextLanguage(false)
        .clearOverridesOfType(C.TRACK_TYPE_TEXT)
        .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, textOff);
    selector.setParameters(b.build());
  }

  /** Audio / subtitle tracks of the stream on screen. */
  private Map<String, Object> tracks() {
    List<Map<String, Object>> audio = new ArrayList<>();
    List<Map<String, Object>> text = new ArrayList<>();
    boolean textOff = selector != null && selector.getParameters().disabledTrackTypes.contains(C.TRACK_TYPE_TEXT);
    if (player != null) {
      List<Tracks.Group> groups = player.getCurrentTracks().getGroups();
      for (int g = 0; g < groups.size(); g++) {
        Tracks.Group group = groups.get(g);
        int type = group.getType();
        if (type != C.TRACK_TYPE_AUDIO && type != C.TRACK_TYPE_TEXT) continue;
        for (int t = 0; t < group.length; t++) {
          Format f = group.getTrackFormat(t);
          Map<String, Object> m = new HashMap<>();
          m.put("id", g + ":" + t);
          m.put("label", f.label == null ? "" : f.label);
          m.put("language", f.language == null ? "" : f.language);
          m.put("selected", group.isTrackSelected(t) && !(type == C.TRACK_TYPE_TEXT && textOff));
          m.put("supported", group.isTrackSupported(t));
          if (type == C.TRACK_TYPE_AUDIO) {
            m.put("channels", f.channelCount);
            m.put("codec", f.sampleMimeType == null ? "" : f.sampleMimeType);
            audio.add(m);
          } else {
            text.add(m);
          }
        }
      }
    }
    Map<String, Object> out = new HashMap<>();
    out.put("audio", audio);
    out.put("text", text);
    return out;
  }

  private void selectTrack(int type, @Nullable String id) {
    if (player == null || selector == null) return;
    TrackSelectionParameters.Builder b = selector.getParameters().buildUpon();
    if (id == null) { // subtitles off
      b.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true);
      selector.setParameters(b.build());
      return;
    }
    String[] parts = id.split(":");
    int g = Integer.parseInt(parts[0]);
    int t = Integer.parseInt(parts[1]);
    List<Tracks.Group> groups = player.getCurrentTracks().getGroups();
    if (g < 0 || g >= groups.size()) return;
    TrackGroup tg = groups.get(g).getMediaTrackGroup();
    b.setTrackTypeDisabled(type, false)
        .setOverrideForType(new TrackSelectionOverride(tg, Collections.singletonList(t)));
    selector.setParameters(b.build());
  }

  // ------------------------------------------------------------ state to Dart

  private void send(Map<String, Object> m) {
    if (sink != null) sink.success(m);
  }

  private void sendState() {
    if (sink == null) return;
    Map<String, Object> m = new HashMap<>();
    m.put("event", "state");
    ExoPlayer p = player;
    if (p == null) {
      m.put("idle", true);
      sink.success(m);
      return;
    }
    int st = p.getPlaybackState();
    m.put("playing", p.isPlaying());
    m.put("buffering", st == Player.STATE_BUFFERING);
    m.put("ended", st == Player.STATE_ENDED);
    m.put("idle", st == Player.STATE_IDLE);
    m.put("position", Math.max(0, p.getCurrentPosition()));
    long d = p.getDuration();
    m.put("duration", (d == C.TIME_UNSET || d < 0 || p.isCurrentMediaItemLive()) ? 0 : d);
    m.put("live", p.isCurrentMediaItemLive());
    Format v = p.getVideoFormat();
    VideoSize vs = p.getVideoSize();
    m.put("width", vs.width > 0 ? vs.width : (v != null ? v.width : 0));
    m.put("height", vs.height > 0 ? vs.height : (v != null ? v.height : 0));
    m.put("fps", v != null && v.frameRate > 0 ? (double) v.frameRate : 0.0);
    m.put("codec", v != null && v.sampleMimeType != null ? v.sampleMimeType : "");
    String hdr = "";
    if (v != null && v.colorInfo != null) {
      ColorInfo ci = v.colorInfo;
      if (ci.colorTransfer == C.COLOR_TRANSFER_ST2084) hdr = "HDR10";
      else if (ci.colorTransfer == C.COLOR_TRANSFER_HLG) hdr = "HLG";
    }
    m.put("hdr", hdr);
    if (lastError != null) m.put("error", lastError);
    sink.success(m);
  }

  // ------------------------------------------------------------ calls from Dart

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    try {
      switch (call.method) {
        case "awake": {
          boolean flag = activity != null
              && (activity.getWindow().getAttributes().flags & WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0;
          result.success(flag);
          break;
        }
        case "open": {
          String url = call.argument("url");
          String ua = call.argument("userAgent");
          Number start = call.argument("startMs");
          open(url, ua == null ? "A3N" : ua, start == null ? 0 : start.longValue());
          result.success(null);
          break;
        }
        case "stop":
          if (player != null) {
            player.stop();
            player.clearMediaItems();
          }
          lastError = null;
          result.success(null);
          break;
        case "play":
          if (player != null) player.play();
          result.success(null);
          break;
        case "pause":
          if (player != null) player.pause();
          result.success(null);
          break;
        case "seek": {
          Number ms = call.argument("ms");
          if (player != null && ms != null) player.seekTo(ms.longValue());
          result.success(null);
          break;
        }
        case "setLanguages": {
          List<String> audio = call.argument("audio");
          List<String> text = call.argument("text");
          Boolean off = call.argument("textOff");
          setLanguages(audio == null ? new ArrayList<>() : audio, text == null ? new ArrayList<>() : text,
              off != null && off);
          result.success(null);
          break;
        }
        case "tracks":
          result.success(tracks());
          break;
        case "selectAudio":
          selectTrack(C.TRACK_TYPE_AUDIO, call.argument("id"));
          result.success(null);
          break;
        case "selectText":
          selectTrack(C.TRACK_TYPE_TEXT, call.argument("id"));
          result.success(null);
          break;
        case "subtitleStyle": {
          Number color = call.argument("color");
          Number scale = call.argument("scale");
          Boolean bg = call.argument("background");
          Number op = call.argument("opacity");
          if (color != null) subColor = color.intValue();
          if (scale != null) subScale = scale.floatValue();
          if (bg != null) subBackground = bg;
          if (op != null) subBgOpacity = op.floatValue();
          for (PlayerView v : views) styleSubtitles(v);
          result.success(null);
          break;
        }
        case "release":
          release();
          result.success(null);
          break;
        default:
          result.notImplemented();
      }
    } catch (Exception e) {
      result.error("A3N_EXO", e.toString(), null);
    }
  }

  private void styleSubtitles(PlayerView v) {
    SubtitleView s = v.getSubtitleView();
    if (s == null) return;
    int bg = subBackground ? Color.argb(Math.round(subBgOpacity * 255), 0, 0, 0) : Color.TRANSPARENT;
    s.setStyle(new CaptionStyleCompat(subColor, bg, Color.TRANSPARENT,
        subBackground ? CaptionStyleCompat.EDGE_TYPE_NONE : CaptionStyleCompat.EDGE_TYPE_OUTLINE,
        Color.BLACK, Typeface.DEFAULT_BOLD));
    s.setFractionalTextSize(SubtitleView.DEFAULT_TEXT_SIZE_FRACTION * subScale);
    s.setApplyEmbeddedStyles(false);
    s.setApplyEmbeddedFontSizes(false);
  }

  // ------------------------------------------------------------ the picture

  private class ViewFactory extends PlatformViewFactory {
    ViewFactory() { super(StandardMessageCodec.INSTANCE); }

    @NonNull @Override
    public PlatformView create(Context ctx, int id, @Nullable Object args) {
      final PlayerView v = new PlayerView(ctx);
      v.setUseController(false);
      v.setShutterBackgroundColor(Color.BLACK);
      v.setBackgroundColor(Color.BLACK);
      v.setResizeMode(AspectRatioFrameLayout.RESIZE_MODE_FIT);
      v.setKeepContentOnPlayerReset(false);
      // Never take the remote's focus from the app.
      v.setFocusable(false);
      v.setFocusableInTouchMode(false);
      v.setDescendantFocusability(ViewGroup.FOCUS_BLOCK_DESCENDANTS);
      v.setLayoutParams(new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
      styleSubtitles(v);
      views.add(v);
      v.setKeepScreenOn(awake);
      v.setPlayer(ensurePlayer());
      return new PlatformView() {
        @Override public View getView() { return v; }
        @Override public void dispose() {
          views.remove(v);
          v.setPlayer(null);
        }
      };
    }
  }
}
