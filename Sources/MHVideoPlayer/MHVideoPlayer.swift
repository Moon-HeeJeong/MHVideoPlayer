import Foundation
import AVKit
import MediaPlayer

//protocol MHVideoPlayerViewDelegate: AnyObject{
//    func mhVideoPlayerCallback(loadStart playerView: MHVideoPlayerView)
//    func mhVideoPlayerCallback(lodaFinished playerView: MHVideoPlayerView, isLoadSuccess: Bool, error: Error?)
//    func mhVideoPlayerCallback(playerView: MHVideoPlayerView, statusPlayer: AVPlayer.Status, error: Error?)
//    func mhVideoPlayerCallback(playerView: MHVideoPlayerView, statusItemPlayer: AVPlayerItem.Status, error: Error?)
//    func mhVideoPlayerCallback(playerView: MHVideoPlayerView, loadedTimeRanges: [CMTimeRange])
//    func mhVideoPlayerCallback(playerView: MHVideoPlayerView, duration: Double)
//    func mhVideoPlayerCallback(playerView: MHVideoPlayerView, currentTime: Double)
//    func mhVideoPlayerCallback(playerView: MHVideoPlayerView, rate: Float)
//    func mhVideoPlayerCallback(playerView: MHVideoPlayerView, isLikelyKeepUp: Bool)
//    func mhVideoPlayerCallback(playerFinished playerView: MHVideoPlayerView)
//}

public enum MHVideoPlayerViewFillModeType{
    case resizeAspect
    case resizeAspectFill
    case resize
    
    var AVLayerVideoGravity: AVLayerVideoGravity{
        get{
            switch self {
            case .resizeAspect:
                return .resizeAspect
            case .resizeAspectFill:
                return .resizeAspectFill
            case .resize:
                return .resize
            }
        }
    }
}

public struct PlayingInfo{ //백그라운드 컨트롤러에서 띄울 플레이어 정보
    let titleStr: String
    let imgUrlStr: String?
    
    public init(titleStr: String, imgUrlStr: String?) {
        self.titleStr = titleStr
        self.imgUrlStr = imgUrlStr
    }
}

public class MHVideoPlayerView: UIView{
    
    deinit{
        print("deinit \(self)")
        self.removePlayer()
    }
    
    public typealias PlayerLoadStart = (_ playerView: MHVideoPlayerView)->()
    public typealias PlayerLoadFinish = (_ playerView: MHVideoPlayerView, _ isLoadSuccess: Bool, _ error: Error?)->()
    public typealias PlayerStatus = (_ playerView: MHVideoPlayerView, _ statusPlayer: AVPlayer.Status, _ error: Error?)->()
    public typealias PlayerItemStatus = (_ playerView: MHVideoPlayerView, _ statusItemPlayer: AVPlayerItem.Status, _ error: Error?)->()
    public typealias PlayerLoadedTimeRanges = (_ playerView: MHVideoPlayerView, _ loadedTimeRanges: [CMTimeRange])->()
    public typealias PlayerDuration = (_ playerView: MHVideoPlayerView, _ duration: Double)->()
    public typealias PlayerCurrentTime = (_ playerView: MHVideoPlayerView, _ currentTime: Double)->()
    public typealias PlayerRate = (_ playerView: MHVideoPlayerView, _ rate: Float)->()
    public typealias PlayerIsLikeyKeepUp = (_ playerView: MHVideoPlayerView, _ isLikelyKeepUp: Bool)->()
    public typealias PlayerFinished = (_ playerView: MHVideoPlayerView)->()
    
    public var playerLoadStartClosure: PlayerLoadStart?
    public var playerLoadFinishClosure: PlayerLoadFinish?
    public var playerStatusClosure: PlayerStatus?
    public var playerItemStatusClosure: PlayerItemStatus?
    public var playerLoadedTimeRangesClosure: PlayerLoadedTimeRanges?
    public var playerDurationClosure: PlayerDuration?
    public var playerCurrentTimeClosure: PlayerCurrentTime?
    public var playerRateClosure: PlayerRate?
    public var playerIsLikeyKeepUpClosure: PlayerIsLikeyKeepUp?
    public var playerFinishedClosure: PlayerFinished?
    
    
    private var statusContext = true
    private var statusItemContext = true
    private var statusKeepUpContext = true
    private var loadedContext = true
    private var durationContext = true
    private var currentTimeContext = true
    private var rateContext = true
    private var playerItemContext = true
    
    private let tPlayerTracksKey = "tracks"
    private let tPlyerPlayableKey = "playable"
    private let tPlayerDurationKey = "duration"
    private let tPlayerRateKey = "rate"
    private let tCurrentItemKey = "currentItem"
    
    private let tPlayerStatusKey = "status"
    private let tPlayerEmptyBufferKey = "playbackBufferEmpty"
    private let tPlaybackBufferFullKey = "playbackBufferFull"
    private let tPlayerKeepUpKey = "playbackLikelyToKeepUp"
    private let tLoadedTimeRangesKey = "loadedTimeRanges"
    
//    weak var delegate: MHVideoPlayerViewDelegate?
    
    public override class var layerClass: AnyClass{
        AVPlayerLayer.self
    }
    
    private var playerLayer: AVPlayerLayer{
        self.layer as! AVPlayerLayer
    }
    
    private var player: AVPlayer?{
        set{
            playerLayer.player = newValue
        }
        get{
            return playerLayer.player
        }
    }
    
    public var keepingPlayer: AVPlayer = AVPlayer()
    
    private var isCalcurateCurrentTime: Bool = true
    private var timeObserverToken: AnyObject?
    private weak var lastPlayerTimeObserve: AVPlayer?
    
    public var isCanBackgroundPlay: Bool = true
    
    public var isReleasePlayer: Bool{
        set{
            if newValue, self.isCanBackgroundPlay{  //백그라운드 재생 가능하고, 현재 백그라운드인 경우
                self.player = nil
            }else{
                self.player = self.keepingPlayer
                self.play()
            }
        }
        get{
            if let _ = self.playerLayer.player{
                return false
            }else{ //백그라운드
                return true
            }
        }
    }
    
    public var url: URL?{
        didSet{
            guard let url = url else {
                return
            }
            
            print("video url::: \(url)")
            self.preparePlayer(url: url)
        }
    }
    
    public var rate: Float{
        set{
            if newValue == 0{
                self.removeCurrentTimeObserver()
            }else if self.rate == 0 && newValue != 0{
                self.addCurrentTimeObserver()
                self.isCalcurateCurrentTime = true
            }
            self.player?.rate = newValue
        }
        get{
            guard let player = self.player else {
                return 0
            }
            return player.rate
        }
    }
    
    public var currentTime: Double {
        get{
            guard let player = self.player else {
                return 0
            }
            return CMTimeGetSeconds(player.currentTime())
        }
        set{
            guard let timeScale = self.player?.currentItem?.duration.timescale else{
                return
            }
            let newTime = CMTimeMakeWithSeconds(newValue, preferredTimescale: timeScale)
            self.player?.seek(to: newTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        }
    }
    
    public var interval = CMTimeMake(value: 1, timescale: 60){
        didSet{
            if self.rate != 0{
                self.addCurrentTimeObserver()
            }
        }
    }
    
    public var fillMode: MHVideoPlayerViewFillModeType?{
        didSet{
            guard let gravity = self.fillMode?.AVLayerVideoGravity else{
                return
            }
            self.playerLayer.videoGravity = gravity
        }
    }
    
    public var playingInfo: PlayingInfo?{
        didSet{
            guard let info = self.playingInfo else{
                return
            }
            self.setupNowPlaying(playingInfo: info)
        }
    }
    
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidPlayToEndTime(notification:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
        self.soundEnableAtBibrationOff()
        
        
        /** 백그라운드로 들어갔을 때 **/
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            print("go background")
            self?.player = nil
        }
        /** 앱으로 들어갔을 때 **/
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            print("comback app")
            self?.player = self?.keepingPlayer
        }
        
        self.setupRemoteTransportControls()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        fatalError("init(coder:) has not been implemented")
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidPlayToEndTime(notification:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    /** 플레이어 준비 **/
    private func preparePlayer(url: URL){
        
//        self.delegate?.mhVideoPlayerCallback(loadStart: self)
        self.playerLoadStartClosure?(self)
        
        let asset = AVURLAsset(url: url)
        let requestKeys: [String] = [tPlayerTracksKey, tPlyerPlayableKey, tPlayerDurationKey]
        
        asset.loadValuesAsynchronously(forKeys: requestKeys) {
            DispatchQueue.main.async {
                for key in requestKeys{
                    var error: NSError?
                    let status = asset.statusOfValue(forKey: key, error: &error)
                    if status == .failed{
//                        self.delegate?.mhVideoPlayerCallback(lodaFinished: self, isLoadSuccess: false, error: error)
                        self.playerLoadFinishClosure?(self, false, error)
                        return
                    }
                    if asset.isPlayable == false{
                        self.playerLoadFinishClosure?(self, false, error)
//                        self.delegate?.mhVideoPlayerCallback(lodaFinished: self, isLoadSuccess: false, error: error)
                        return
                    }
                }
                
                if self.player == nil {
                    self.player = self.keepingPlayer
                }
                
                self.keepingPlayer.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                
               self.player?.currentItem?.audioTimePitchAlgorithm = .timeDomain

                self.addObserversPlayer(avPlayer: self.player!)
                self.addObserversVideoItem(playerItem: self.player!.currentItem!)
//                self.delegate?.mhVideoPlayerCallback(lodaFinished: self, isLoadSuccess: true, error: nil)
                self.playerLoadFinishClosure?(self, true, nil)
            }
        }
    }

    /** 백그라운드 재생 컨트롤러 터치이벤트 셋업 **/
    private func setupRemoteTransportControls(){
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [unowned self] event in
            self.keepingPlayer.play()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [unowned self] event in
            self.keepingPlayer.pause()
            return .success
        }
    }
    
    /** 백그라운드 재생 컨트롤러에 뜰 정보 셋업 **/
    func setupNowPlaying(playingInfo: PlayingInfo){
        var nowPlayingInfo = [String : Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = playingInfo.titleStr
        
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.player?.currentTime().seconds
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = self.player?.currentItem?.asset.duration.seconds
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = self.player?.rate
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        
        guard let urlStr = playingInfo.imgUrlStr else{
            return
        }
        
        let url = URL(string: urlStr)!
        
        guard let data = try? Data(contentsOf: url) else{
            return
        }
        
        if let image = UIImage(data: data){
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { size in
                return image
            })
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func soundEnableAtBibrationOff(){
        do{
            try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        }catch{}
    }
    
    private func addObserversPlayer(avPlayer: AVPlayer){
        avPlayer.addObserver(self, forKeyPath: tPlayerStatusKey, options: [.new], context: &statusContext)
        avPlayer.addObserver(self, forKeyPath: tPlayerRateKey, options: [.new], context: &rateContext)
        avPlayer.addObserver(self, forKeyPath: tCurrentItemKey, options: [.old, .new], context: &playerItemContext)
    }
    
    private func removeObserversPlayer(avPlayer: AVPlayer){
        avPlayer.removeObserver(self, forKeyPath: tPlayerStatusKey, context: &statusContext)
        avPlayer.removeObserver(self, forKeyPath: tPlayerRateKey, context: &rateContext)
        avPlayer.removeObserver(self, forKeyPath: tCurrentItemKey, context: &playerItemContext)
        
        if let timeObserverToken = self.timeObserverToken {
            avPlayer.removeTimeObserver(timeObserverToken)
        }
    }
    
    private func addObserversVideoItem(playerItem: AVPlayerItem){
        playerItem.addObserver(self, forKeyPath: tLoadedTimeRangesKey, options: [], context: &loadedContext)
        playerItem.addObserver(self, forKeyPath: tPlayerDurationKey, options: [], context: &durationContext)
        playerItem.addObserver(self, forKeyPath: tPlayerStatusKey, options: [], context: &statusItemContext)
        playerItem.addObserver(self, forKeyPath: tPlayerKeepUpKey, options: [.new, .old], context: &statusKeepUpContext)
    }
    
    private func removeObserversVideoItem(playerItem: AVPlayerItem){
        playerItem.removeObserver(self, forKeyPath: tLoadedTimeRangesKey, context: &loadedContext)
        playerItem.removeObserver(self, forKeyPath: tPlayerDurationKey, context: &durationContext)
        playerItem.removeObserver(self, forKeyPath: tPlayerStatusKey, context: &statusItemContext)
        playerItem.removeObserver(self, forKeyPath: tPlayerKeepUpKey, context: &statusKeepUpContext)
    }
    
    private func removeCurrentTimeObserver(){
        if let timeObserverToken = self.timeObserverToken {
            lastPlayerTimeObserve?.removeTimeObserver(timeObserverToken)
        }
        self.timeObserverToken = nil
    }
    
    private func addCurrentTimeObserver(){
        self.removeCurrentTimeObserver()
        
        self.lastPlayerTimeObserve = self.player
        self.timeObserverToken = self.player?.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main, using: { [weak self] time-> Void in
            if let mySelf = self{
                if mySelf.isCalcurateCurrentTime{
//                    self?.delegate?.mhVideoPlayerCallback(playerView: mySelf, currentTime: mySelf.currentTime)
                    self?.playerCurrentTimeClosure?(mySelf, mySelf.currentTime)
                }
            }
        }) as AnyObject?
    }
    
    private func removePlayer(){
        guard let player = player else {
            return
        }
        player.pause()
        
        self.removeObserversPlayer(avPlayer: player)
        
        if let playerItem = player.currentItem{
            self.removeObserversVideoItem(playerItem: playerItem)
        }
        
        self.player = nil
    }
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == &statusContext {
            guard let player = self.player else {
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
                return
            }
//            self.delegate?.mhVideoPlayerCallback(playerView: self, statusPlayer: player.status, error: player.error)
            self.playerStatusClosure?(self, player.status, player.error)
            
        }else if context == &loadedContext{
            let playerItem = self.player?.currentItem
            
            guard let times = playerItem?.loadedTimeRanges else{
                return
            }
            let values = times.map{$0.timeRangeValue}
//            self.delegate?.mhVideoPlayerCallback(playerView: self, loadedTimeRanges: values)
            self.playerLoadedTimeRangesClosure?(self, values)
            
        }else if context == &durationContext{
            if let currentItem = self.player?.currentItem{
//                self.delegate?.mhVideoPlayerCallback(playerView: self, duration: currentItem.duration.seconds)
                self.playerDurationClosure?(self, currentItem.duration.seconds)
            }
        }else if context == &statusItemContext{
            if let currentItem = self.player?.currentItem{
//                self.delegate?.mhVideoPlayerCallback(playerView: self, statusItemPlayer: currentItem.status, error: currentItem.error)
                self.playerItemStatusClosure?(self, currentItem.status, currentItem.error)
            }
        }else if context == &rateContext{
            guard let newRateNumber = change?[NSKeyValueChangeKey.newKey] as? NSNumber else{
                return
            }
            let newRate = newRateNumber.floatValue
            if newRate == 0{
                self.removeCurrentTimeObserver()
            }else{
                self.addCurrentTimeObserver()
            }
//            self.delegate?.mhVideoPlayerCallback(playerView: self, rate: newRate)
            self.playerRateClosure?(self, newRate)
            
        }else if context == &statusKeepUpContext{
            guard let newIsKeepupValue = (change?[NSKeyValueChangeKey.newKey] as? Bool) else{
                return
            }
//            self.delegate?.mhVideoPlayerCallback(playerView: self, isLikelyKeepUp: newIsKeepupValue)
            self.playerIsLikeyKeepUpClosure?(self, newIsKeepupValue)
            
        }else if context == &playerItemContext{
            guard let oldItem = (change?[NSKeyValueChangeKey.oldKey] as? AVPlayerItem) else{
                return
            }
            self.removeObserversVideoItem(playerItem: oldItem)
            guard let newItem = (change?[NSKeyValueChangeKey.newKey] as? AVPlayerItem) else{
                return
            }
            self.addObserversVideoItem(playerItem: newItem)
        }else{
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    
    
}

extension MHVideoPlayerView{
    @objc private func playerItemDidPlayToEndTime(notification: NSNotification){
//        self.delegate?.mhVideoPlayerCallback(playerFinished: self)
        
        self.playerFinishedClosure?(self)
    }
}

extension MHVideoPlayerView{
    public func play(rate: Float = 1){
        self.rate = rate
    }
    
    public func pause(){
        self.isCalcurateCurrentTime = false
        self.rate = 0
    }
    
    public func stop(){
        self.currentTime = 0
        self.pause()
    }
    public func playFromBeginning(){
        self.player?.seek(to: CMTime.zero)
        self.player?.play()
    }
    
}

extension MHVideoPlayerView{
    func setPlayerLoadStartClosure(closure: @escaping PlayerLoadStart){
        self.playerLoadStartClosure = closure
    }
    func setPlayerLoadFinishClosure(closure: @escaping PlayerLoadFinish){
        self.playerLoadFinishClosure = closure
    }
    func setPlayerStatusClosure(closure: @escaping PlayerStatus){
        self.playerStatusClosure = closure
    }
    func setPlayerItemStatusClosure(closure: @escaping PlayerItemStatus){
        self.playerItemStatusClosure = closure
    }
    func setPlayerLoadedTimeRangesClosure(closure: @escaping PlayerLoadedTimeRanges){
        self.playerLoadedTimeRangesClosure = closure
    }
    func setPlayerDurationClosure(closure: @escaping PlayerDuration){
        self.playerDurationClosure = closure
    }
    func setPlayerCurrentTimeClosure(closure: @escaping PlayerCurrentTime){
        self.playerCurrentTimeClosure = closure
    }
    func setPlayerRateClosure(closure: @escaping PlayerRate){
        self.playerRateClosure = closure
    }
    func setPlayerIsLikeyKeepUpClosure(closure: @escaping PlayerIsLikeyKeepUp){
        self.playerIsLikeyKeepUpClosure = closure
    }
    func setPlayerFinishedClosure(closure: @escaping PlayerFinished){
        self.playerFinishedClosure = closure
    }
    
}
