#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>

@interface CRHelper : NSObject
-(void) synchronizeTimesFromCurrent:(NSDictionary *)timer;
-(void) fadeOutPlayingItem:(AVQueuePlayer *)player;
@end

static void prefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
BOOL prefsEnabled;

id observerToRetain = nil;
CRHelper *_helper = nil;

%group main

%hook AVQueuePlayer
- (void)insertItem:(AVPlayerItem *)itemn afterItem:(id)arg2 {
    %orig;

    if (observerToRetain) {
        [self removeTimeObserver:observerToRetain]; // Remove any previous observers.
    }

    Float64 duration = CMTimeGetSeconds(self.currentItem.asset.duration);
    CMTime time = CMTimeMakeWithSeconds(duration - 10, 600);
    NSArray *times = @[ [NSValue valueWithCMTime:time] ];

    __block AVQueuePlayer *bself = self;

    observerToRetain = [self addBoundaryTimeObserverForTimes:times queue:NULL usingBlock:^{
        AVPlayerItem *current = bself.currentItem;

        if (current && prefsEnabled) {
            AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:[(AVURLAsset *)current.asset URL] error:NULL];
            Float64 toSeek = CMTimeGetSeconds(current.currentTime) + 2.0f;
            player.currentTime = toSeek;
            [player prepareToPlay];
            [player playAtTime:player.deviceCurrentTime + 2.0f];
            player.volume = 1.0f;

            NSDictionary *userInfo = @{
                @"player": player,
                @"current": current,
                @"bself": bself,
                @"toSeek": @(toSeek)
            };

            if (_helper == nil) {
                _helper = [[CRHelper alloc] init];
            }

            [_helper fadeOutPlayingItem:bself]; // Fade out the currently playing item.
            [NSThread detachNewThreadSelector:@selector(synchronizeTimesFromCurrent:) toTarget:_helper withObject:userInfo];
        }
    }];
}
%end

@implementation CRHelper
// Synchronize playback for crossfade
-(void) synchronizeTimesFromCurrent:(NSDictionary *)timer {
    NSDictionary *players = timer;

    AVAudioPlayer *player = players[@"player"];
    AVPlayerItem *current = players[@"current"];
    AVQueuePlayer *bself = players[@"bself"];
    Float64 toSeek = [players[@"toSeek"] floatValue];

    BOOL madeFade = NO;

    while (1) {
        if ([bself.currentItem isEqual:current] && player.currentTime > toSeek + 0.01) {
            [bself performSelectorOnMainThread:@selector(advanceToNextItem) withObject:nil waitUntilDone:YES];
        }

        if (![bself.currentItem isEqual:current] && player.currentTime > toSeek + 0.01) {
            Float64 timeout = player.currentTime - toSeek;
            if (timeout < 0.0f) timeout = 0.0f;
            if (timeout > 7.0f) timeout = 7.0f;

            Float64 outVolume = (7.0f - timeout) / 7.0f;
            player.volume = outVolume;

            if (madeFade == NO) {
                [self performSelectorOnMainThread:@selector(makeFadeIn:) withObject:bself waitUntilDone:YES];
                madeFade = YES;
            }
        }

        if (player.currentTime == 0.0f) {
            break;
        }

        [NSThread sleepForTimeInterval:0.1];
    }
}

-(void) makeFadeIn:(AVQueuePlayer *)bself {
    NSArray *audioTracks = [bself.currentItem.asset tracksWithMediaType:AVMediaTypeAudio];
    NSMutableArray *allAudioParams = [NSMutableArray array];

    for (AVAssetTrack *track in audioTracks) {
        AVMutableAudioMixInputParameters *audioInputParams = [AVMutableAudioMixInputParameters audioMixInputParameters];
        [audioInputParams setVolumeRampFromStartVolume:0.0
                                           toEndVolume:1.0
                                              timeRange:CMTimeRangeMake(CMTimeMakeWithSeconds(0, 1), CMTimeMakeWithSeconds(7, 1))]; // hope to change this with a slider in the next version
        [audioInputParams setTrackID:[track trackID]];
        [allAudioParams addObject:audioInputParams];
    }

    AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
    [audioMix setInputParameters:allAudioParams];
    [bself.currentItem setAudioMix:audioMix];
}

// New fade out function for the current song hopefully
-(void) fadeOutPlayingItem:(AVQueuePlayer *)bself {
    // Get the total duration of the song
    CMTime totalDuration = bself.currentItem.asset.duration;
    
    // Calculate when the fade-out should start, i.e., 7 seconds before the end
    // Add a buffer, let's say, 1-2 seconds before the fade-out starts
    CMTime fadeOutStartTime = CMTimeSubtract(totalDuration, CMTimeMakeWithSeconds(10, 600));  // 9 seconds fade out + 1 buffer (hope to change this with a slider in the next update)
    
    NSArray *audioTracks = [bself.currentItem.asset tracksWithMediaType:AVMediaTypeAudio];
    NSMutableArray *allAudioParams = [NSMutableArray array];

    for (AVAssetTrack *track in audioTracks) {
        AVMutableAudioMixInputParameters *audioInputParams = [AVMutableAudioMixInputParameters audioMixInputParameters];
        
        // Set the fade-out to go from full volume to 0, starting at fadeOutStartTime and lasting 7 seconds
        [audioInputParams setVolumeRampFromStartVolume:1.0
                                           toEndVolume:0.0
                                              timeRange:CMTimeRangeMake(fadeOutStartTime, CMTimeMakeWithSeconds(9, 600))]; //hope to change this in the next update with a slider to change how long each fade will be
        [audioInputParams setTrackID:[track trackID]];
        [allAudioParams addObject:audioInputParams];
    }

    //AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
    //[audioMix setInputParameters:allAudioParams];
    //[bself.currentItem setAudioMix:audioMix];
}

@end

%end

static void prefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/org.h6nry.crossfade-musicprefs-hook.plist"];
    if (prefs == nil) {
        prefs = [NSDictionary dictionary];
    }

    id value = [prefs objectForKey:@"MusicCrossfadeEnabledSetting"];
    prefsEnabled = (value == nil || [value isEqual:@YES]);
}

%ctor {
    CFStringRef notificationName = CFSTR("org.h6nry.crossfade/prefs-changed");
    CFNotificationCenterRef notificationCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(notificationCenter, NULL, prefsChangedCallback, notificationName, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    prefsChangedCallback(nil, nil, nil, nil, nil);

    if (prefsEnabled) {
        %init(main);
    }
}
