import Foundation
import AVFoundation
import RealityKit

@MainActor enum SoundBank {
    enum Cue:String,CaseIterable { case hit="Hit1", hitAlt="Hit2", win="Win", miss="Miss", net="Net", serve="Serve", step="Step", target="Target", menu="Menu", select="Select", pause="Pause" }
    private static var voices:[Cue:[AVAudioPlayer]]=[:]
    private static var resources:[Cue:AudioFileResource]=[:]
    private static var music:AVAudioPlayer?
    private static var ready=false,preparing=false
    private static var desiredMusic:Float=0
    private static var effects:Float=0.65
    static func prepare() {
        guard !ready,!preparing else { return }; preparing=true
        DispatchQueue.global(qos:.userInitiated).async {
            let session=AVAudioSession.sharedInstance()
            let success:Bool
            do { try session.setCategory(.ambient,mode:.default,options:[.mixWithOthers]); try session.setActive(true); success=true }
            catch { success=false }
            Task { @MainActor in
                preparing=false; ready=success
                guard success else { return }
                for cue in Cue.allCases {
                    guard let url=url(cue.rawValue) else { continue }
                    voices[cue]=(0..<3).compactMap { _ in try? AVAudioPlayer(contentsOf:url) }
                    voices[cue]?.forEach { $0.prepareToPlay() }
                }
                if let url=url("ClubLoop") {
                    music=try? AVAudioPlayer(contentsOf:url); music?.numberOfLoops = -1; music?.volume=0; music?.prepareToPlay()
                }
                applyMusic()
                for cue in [Cue.hit,.hitAlt,.net,.serve,.step] {
                    if let url=url(cue.rawValue),let resource=try? await AudioFileResource(contentsOf:url) { resources[cue]=resource }
                }
            }
        }
    }
    static func configure(musicEnabled:Bool,musicVolume:Float,effectsVolume:Float,paused:Bool=false) {
        desiredMusic=musicEnabled ? min(1,max(0,musicVolume))*(paused ? 0.22:1):0
        effects=min(1,max(0,effectsVolume))
        if ready { applyMusic() } else if desiredMusic > 0 { prepare() }
    }
    private static func applyMusic() {
        guard let music else { return }
        if desiredMusic > 0,!music.isPlaying { music.play() }
        music.setVolume(desiredMusic*0.38,fadeDuration:0.35)
        if desiredMusic == 0 { music.pause() }
    }
    static func play(_ cue:Cue,strength:Float=1,at entity:Entity?=nil) {
        guard effects > 0 else { return }
        guard ready else { prepare(); return }
        let volume=effects*min(1,max(0.18,strength))
        if let entity,let resource=resources[cue] {
            entity.components.set(SpatialAudioComponent(gain:Audio.Decibel(-9+20*log10(max(0.01,volume))),reverbLevel:Audio.Decibel(-15)))
            entity.playAudio(resource); return
        }
        guard let pool=voices[cue],let voice=pool.first(where:{ !$0.isPlaying }) ?? pool.first else { return }
        voice.currentTime=0; voice.volume=volume*(cue == .step ? 0.14 : 0.45); voice.play()
    }
    private static func url(_ name:String) -> URL? {
        Bundle.main.url(forResource:name,withExtension:"wav") ?? Bundle.main.url(forResource:name,withExtension:"wav",subdirectory:"Audio")
    }
}
