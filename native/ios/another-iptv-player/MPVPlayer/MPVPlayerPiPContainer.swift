import AVKit
import Combine
import CoreMedia
import SwiftUI
import UIKit

/// `AVSampleBufferDisplayLayer` + libmpv + Picture-in-Picture (sample buffer API, iOS 15+).
///
/// Mimari:
/// - `PixelBufferDisplayView` içindeki `AVSampleBufferDisplayLayer` hem inline render hem PiP
///   content source olarak kullanılır.
/// - PiP başlarken/kapanırken görünüm taşınmaz (eski video call API'deki reparenting çıktı);
///   sistem layer'ı doğrudan PiP penceresine kompoze eder. Inline görünümü `PlayerView`'deki
///   SwiftUI overlay ("Picture in Picture") örtüyor.
/// - Oynat/duraklat/skip PiP kontrolleri `AVPictureInPictureSampleBufferPlaybackDelegate`
///   üzerinden mpv'ye forward edilir.
final class MPVPlayerContainerViewController: UIViewController {
  private let mpvPlayer: MPVPlayer
  weak var playbackBridge: VideoPlayerController?

  private let displayView = PixelBufferDisplayView()
  private var pipController: AVPictureInPictureController?
  private var didConfigureMpv = false
  private var appLifecycleObservers: [NSObjectProtocol] = []
  /// willResignActive ve didEnterBackground için ayrı iş öğeleri — biri diğerini iptal etmesin.
  private var pendingResignPiPStart: DispatchWorkItem?
  private var pendingBackgroundPiPStart: DispatchWorkItem?
  private var currentVideoContentMode: UIView.ContentMode = .scaleAspectFit
  private var cancellables = Set<AnyCancellable>()

  /// SwiftUI'den manuel PiP tetiklemek için artan sayaç.
  var lastProcessedManualPiPTrigger: Int = 0

  init(mpvPlayer: MPVPlayer, playbackBridge: VideoPlayerController?) {
    self.mpvPlayer = mpvPlayer
    self.playbackBridge = playbackBridge
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    pendingResignPiPStart?.cancel()
    pendingBackgroundPiPStart?.cancel()
    for o in appLifecycleObservers {
      NotificationCenter.default.removeObserver(o)
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    edgesForExtendedLayout = .all

    // Autoresizing mask: layout passı olmadan container değişimlerini takip eder.
    displayView.translatesAutoresizingMaskIntoConstraints = true
    displayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    displayView.frame = view.bounds
    view.addSubview(displayView)

    configureMpvIfNeeded()
    displayView.setVideoContentMode(currentVideoContentMode)
    setupPiP()
    setupAutoPiPOnBackground()
    observeMpvPlaybackState()
  }

  func setVideoContentMode(_ mode: UIView.ContentMode) {
    currentVideoContentMode = mode
    if isViewLoaded {
      displayView.setVideoContentMode(mode)
    }
  }

  private func configureMpvIfNeeded() {
    guard !didConfigureMpv else { return }
    didConfigureMpv = true
    mpvPlayer.configure(
      enableHardwareAcceleration: true,
      onVideoSizeChange: { _ in },
      onFrame: { [weak self] buffer, _, flip in
        self?.displayView.enqueuePixelBuffer(buffer, flipVerticalForOpenGL: flip)
      }
    )
  }

  private func setupPiP() {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
    let source = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: displayView.sampleBufferDisplayLayer,
      playbackDelegate: self
    )
    let pip = AVPictureInPictureController(contentSource: source)
    pip.delegate = self
    // Otomatik inline PiP: paused/idle iken yanlışlıkla devreye girmesin — bizim guard'larımız tetikler.
    pip.canStartPictureInPictureAutomaticallyFromInline = false
    pipController = pip
  }

  /// mpv oynatma durumu değişince PiP üst çubuğundaki play/pause ikonu ve zaman aralığı
  /// güncellensin diye sistem state'i invalide edilir.
  ///
  /// Aynı zamanda VOD ilk açılışta mpv duration'ı henüz okumadan PiP'in `timeRangeForPlayback`'i
  /// sorgulamasının önüne geçer: duration 0 iken canlı aralık döndürüyoruz → duration gelince
  /// invalidate → sistem yeniden sorgular → doğru VOD aralığı (pause butonu).
  private func observeMpvPlaybackState() {
    mpvPlayer.$isPaused
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.pipController?.invalidatePlaybackState()
      }
      .store(in: &cancellables)

    mpvPlayer.$duration
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.pipController?.invalidatePlaybackState()
      }
      .store(in: &cancellables)

    mpvPlayer.$isPlaybackEstablished
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.pipController?.invalidatePlaybackState()
      }
      .store(in: &cancellables)
  }

  /// `willResignActive` gelince iki deneme yapar:
  /// 1) 80ms sonra — mpv state kesinleşmiş, sistem PiP penceresi hâlâ açık.
  /// 2) 160ms sonra — bazı cihazlarda sistem biraz daha geç hazır oluyor.
  /// `didEnterBackground` kullanılmaz: o noktada `isPictureInPicturePossible` genellikle false.
  private func setupAutoPiPOnBackground() {
    let obs = NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.autoPiPOnResignActive()
    }
    appLifecycleObservers = [obs]
  }

  private func autoPiPOnResignActive() {
    pendingResignPiPStart?.cancel()
    pendingBackgroundPiPStart?.cancel()
    schedulePiPAttempt(delay: 0.08, storeIn: &pendingResignPiPStart)
    schedulePiPAttempt(delay: 0.16, storeIn: &pendingBackgroundPiPStart)
  }

  private func schedulePiPAttempt(delay: TimeInterval, storeIn slot: inout DispatchWorkItem?) {
    let item = DispatchWorkItem { [weak self] in self?.attemptPiPStart() }
    slot = item
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
  }

  private func attemptPiPStart() {
    guard let pip = pipController,
          !pip.isPictureInPictureActive,
          isActivelyPlayingForPiP
    else { return }
    pip.startPictureInPicture()
  }

  func processManualPiPTrigger(_ value: Int) {
    guard value != lastProcessedManualPiPTrigger else { return }
    lastProcessedManualPiPTrigger = value
    startPiPIfPossible()
  }

  func startPiPIfPossible() {
    guard let pip = pipController,
          pip.isPictureInPicturePossible,
          !pip.isPictureInPictureActive
    else { return }
    guard isActivelyPlayingForPiP else { return }
    pip.startPictureInPicture()
  }

  /// PiP başlatma için minimum kontrol: mpv hazır ve en az bir frame gelmiş olsun.
  private var isActivelyPlayingForPiP: Bool {
    mpvPlayer.isReady && mpvPlayer.isPlaybackEstablished
  }
}

// MARK: - AVPictureInPictureControllerDelegate

extension MPVPlayerContainerViewController: AVPictureInPictureControllerDelegate {
  func pictureInPictureControllerWillStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    // Sample buffer content source: reparent yok. Inline overlay placeholder didStart'ta yansıtılır.
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    playbackBridge?.isPiPActive = true
  }

  func pictureInPictureControllerWillStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    // nothing
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    playbackBridge?.isPiPActive = false
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    playbackBridge?.isPiPActive = false
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(true)
  }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension MPVPlayerContainerViewController: AVPictureInPictureSampleBufferPlaybackDelegate {
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {
    if playing {
      mpvPlayer.play()
    } else {
      mpvPlayer.pause()
    }
  }

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    // Canlı yayında skip kontrollerini gizlemek için öncelikli olarak bridge bayrağını oku;
    // mpv `duration` bazı canlı kaynaklarda pozitif dönebiliyor (EPG / cache süresi).
    if playbackBridge?.isLiveStream == true {
      return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    let durationSec = mpvPlayer.duration
    if durationSec > 0, durationSec.isFinite {
      let start = CMTime(value: 0, timescale: 600)
      let duration = CMTime(seconds: durationSec, preferredTimescale: 600)
      return CMTimeRange(start: start, duration: duration)
    }
    // Süre henüz bilinmiyor: sonsuz aralık ver; duration gelince observer invalidate eder.
    return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    mpvPlayer.isPaused
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {
    // Layer otomatik yeniden boyutlanır; özel işlem gerekmez.
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    // Control Center ve merkez transport butonlarıyla aynı yolu kullan: `jump(seconds:)`
    // `markSeekRequestStart()` üzerinden UI state'ini (scrub / loading) senkronize tutar;
    // doğrudan `mpvPlayer.seek` çağırmak bazı kaynaklarda boşa çıkıyordu.
    let seconds = Int(CMTimeGetSeconds(skipInterval).rounded())
    if let bridge = playbackBridge {
      bridge.jump(seconds: seconds)
    } else {
      let target = mpvPlayer.position + Double(seconds)
      mpvPlayer.seek(to: max(0, target))
    }
    completionHandler()
  }
}

/// `PlayerView` ve demo için: video yüzeyi + PiP.
struct MPVPlayerPlaybackContainerView: UIViewControllerRepresentable {
  @ObservedObject var mpvPlayer: MPVPlayer
  var playbackBridge: VideoPlayerController?
  var manualPiPTrigger: Int

  func makeUIViewController(context: Context) -> MPVPlayerContainerViewController {
    let vc = MPVPlayerContainerViewController(mpvPlayer: mpvPlayer, playbackBridge: playbackBridge)
    vc.lastProcessedManualPiPTrigger = manualPiPTrigger
    vc.setVideoContentMode(playbackBridge?.aspectMode.viewportContentMode ?? .scaleAspectFit)
    return vc
  }

  func updateUIViewController(_ uiViewController: MPVPlayerContainerViewController, context: Context) {
    uiViewController.playbackBridge = playbackBridge
    uiViewController.setVideoContentMode(playbackBridge?.aspectMode.viewportContentMode ?? .scaleAspectFit)
    uiViewController.processManualPiPTrigger(manualPiPTrigger)
  }
}
