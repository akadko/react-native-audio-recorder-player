//  RNAudioRecorderPlayer.m
//  dooboolab
//
//  Created by dooboolab on 16/04/2018.
//  Copyright © 2018 Facebook. All rights reserved.
//

#import "RNAudioRecorderPlayer.h"
#import <React/RCTLog.h>
#import <React/RCTConvert.h>
#import <AVFoundation/AVFoundation.h>
#import "MobileVLCKit/MobileVLCKit.h"

NSString* GetDirectoryOfType_Sound(NSSearchPathDirectory dir) {
  NSArray* paths = NSSearchPathForDirectoriesInDomains(dir, NSUserDomainMask, YES);
  return [paths.firstObject stringByAppendingString:@"/"];
}

@implementation RNAudioRecorderPlayer {
  NSURL *audioFileURL;
  AVAudioRecorder *audioRecorder;
  AVAudioPlayer *audioPlayer;
  VLCMediaPlayer *vlcPlayer;
  NSTimer *recordTimer;
  NSTimer *playTimer;
  BOOL _meteringEnabled;
}
double subscriptionDuration = 0.1;

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
  NSLog(@"audioPlayerDidFinishPlaying");
  NSNumber *duration = [NSNumber numberWithDouble:vlcPlayer.time.intValue];

  // Send last event then finish it.
  // NSString* status = [NSString stringWithFormat:@"{\"duration\": \"%@\", \"current_position\": \"%@\"}", [duration stringValue], [currentTime stringValue]];
  NSDictionary *status = @{
                         @"duration" : [duration stringValue],
                         @"current_position" : [duration stringValue],
                         };
  [self sendEventWithName:@"rn-playback" body: status];
  if (playTimer != nil) {
    [playTimer invalidate];
    playTimer = nil;
  }
}

- (void) mediaPlayerStateChanged:(NSNotification *)aNotification {
  VLCMediaPlayer *player = [aNotification object];
  if (player.state == VLCMediaPlayerStateEnded) {
    NSLog(@"audioPlayerDidFinishPlaying");
    NSNumber *duration = [NSNumber numberWithDouble:vlcPlayer.media.length.intValue];

    // Send last event then finish it.
    NSDictionary *status = @{
                           @"duration" : [duration stringValue],
                           @"current_position" : [duration stringValue],
                           };
    [self sendEventWithName:@"rn-playback" body: status];
    if (playTimer != nil) {
      [playTimer invalidate];
      playTimer = nil;
    }
  }
}


- (void)updateRecorderProgress:(NSTimer*) timer
{
  NSNumber *currentTime = [NSNumber numberWithDouble:audioRecorder.currentTime * 1000];
  // NSString* status = [NSString stringWithFormat:@"{\"current_position\": \"%@\"}", [currentTime stringValue]];
  NSNumber *currentMetering = [NSNumber numberWithDouble:0];
  if (_meteringEnabled) {
      [audioRecorder updateMeters];
      currentMetering = [NSNumber numberWithDouble:[audioRecorder averagePowerForChannel: 0]];
  }

  NSDictionary *status = @{
                         @"current_position" : [currentTime stringValue],
                         @"current_metering" : [currentMetering stringValue],
                         };
  [self sendEventWithName:@"rn-recordback" body:status];
}

- (void)updateProgress:(NSTimer*) timer
{
  NSNumber *currentTime = vlcPlayer.time.value;
  NSNumber *duration = vlcPlayer.media.length.value;

  NSLog(@"updateProgress: %@", currentTime);

  if ([duration intValue] == 0 || currentTime == nil) {
    return;
  }

  NSDictionary *status = @{
                         @"duration" : [duration stringValue],
                         @"current_position" : [currentTime stringValue],
                         };

  [self sendEventWithName:@"rn-playback" body:status];
}

- (void)startRecorderTimer
{
  dispatch_async(dispatch_get_main_queue(), ^{
      self->recordTimer = [NSTimer scheduledTimerWithTimeInterval: subscriptionDuration
                                           target:self
                                           selector:@selector(updateRecorderProgress:)
                                           userInfo:nil
                                           repeats:YES];
  });
}

- (void)startPlayerTimer
{
  dispatch_async(dispatch_get_main_queue(), ^{
      self->playTimer = [NSTimer scheduledTimerWithTimeInterval: subscriptionDuration
                                           target:self
                                           selector:@selector(updateProgress:)
                                           userInfo:nil
                                           repeats:YES];
  });
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE();

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"rn-recordback", @"rn-playback"];
}

RCT_EXPORT_METHOD(setSubscriptionDuration:(double)duration
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
  subscriptionDuration = duration;
  resolve(@"set subscription duration.");
}

RCT_EXPORT_METHOD(startRecorder:(NSString*)path
                  meteringEnabled:(BOOL)meteringEnabled
                  audioSets: (NSDictionary*)audioSets
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {

  NSString *encoding = [RCTConvert NSString:audioSets[@"AVFormatIDKeyIOS"]];
  NSNumber *sampleRate = [RCTConvert NSNumber:audioSets[@"AVSampleRateKeyIOS"]];
  NSNumber *numberOfChannel = [RCTConvert NSNumber:audioSets[@"AVNumberOfChannelsKeyIOS"]];
  NSNumber *avFormat;
  NSNumber *audioQuality = [RCTConvert NSNumber:audioSets[@"AVEncoderAudioQualityKeyIOS"]];
  _meteringEnabled = meteringEnabled;
  NSNumber *avLPCMBitDepth = [RCTConvert NSNumber:audioSets[@"AVLinearPCMBitDepthKeyIOS"]];
  BOOL *avLPCMIsBigEndian = [RCTConvert BOOL:audioSets[@"AVLinearPCMIsBigEndianKeyIOS"]];
  BOOL *avLPCMIsFloatKey = [RCTConvert BOOL:audioSets[@"AVLinearPCMIsFloatKeyIOS"]];
  BOOL *avLPCMIsNonInterleaved = [RCTConvert BOOL:audioSets[@"AVLinearPCMIsNonInterleavedIOS"]];

  if ([path isEqualToString:@"DEFAULT"]) {
      audioFileURL = [NSURL fileURLWithPath:[GetDirectoryOfType_Sound(NSCachesDirectory) stringByAppendingString:@"sound.m4a"]];
  } else {
      if ([path rangeOfString:@"file://"].location == NSNotFound) {
          audioFileURL = [NSURL fileURLWithPath: [GetDirectoryOfType_Sound(NSCachesDirectory) stringByAppendingString:path]];
      } else {
          audioFileURL = [NSURL URLWithString:path];
      }
  }

  if (!sampleRate) {
      sampleRate = [NSNumber numberWithFloat:44100];
  }
  if (!encoding) {
    avFormat = [NSNumber numberWithInt:kAudioFormatAppleLossless];
  } else {
    if ([encoding  isEqual: @"lpcm"]) {
      avFormat =[NSNumber numberWithInt:kAudioFormatLinearPCM];
    } else if ([encoding  isEqual: @"ima4"]) {
      avFormat =[NSNumber numberWithInt:kAudioFormatAppleIMA4];
    } else if ([encoding  isEqual: @"aac"]) {
      avFormat =[NSNumber numberWithInt:kAudioFormatMPEG4AAC];
    } else if ([encoding  isEqual: @"MAC3"]) {
      avFormat =[NSNumber numberWithInt:kAudioFormatMACE3];
    } else if ([encoding  isEqual: @"MAC6"]) {
      avFormat =[NSNumber numberWithInt:kAudioFormatMACE6];
    } else if ([encoding  isEqual: @"ulaw"]) {
      avFormat =[NSNumber numberWithInt:kAudioFormatULaw];
    } else if ([encoding  isEqual: @"alaw"]) {
      avFormat =[NSNumber numberWithInt:kAudioFormatALaw];
    } else if ([encoding  isEqual: @"mp1"]) {
      avFormat =[NSNumber numberWithInt:kAudioFormatMPEGLayer1];
    } else if ([encoding  isEqual: @"mp2"]) {
      avFormat =[NSNumber numberWithInt:kAudioFormatMPEGLayer2];
    } else if ([encoding  isEqual: @"alac"]) {
      avFormat =[NSNumber numberWithInt:kAudioFormatAppleLossless];
    } else if ([encoding  isEqual: @"amr"]) {
      avFormat =[NSNumber numberWithInt:kAudioFormatAMR];
    } else if ([encoding  isEqual: @"flac"]) {
        if (@available(iOS 11, *)) avFormat =[NSNumber numberWithInt:kAudioFormatFLAC];
    } else if ([encoding  isEqual: @"opus"]) {
        if (@available(iOS 11, *)) avFormat =[NSNumber numberWithInt:kAudioFormatOpus];
    }
  }
  if (!numberOfChannel) {
    numberOfChannel = [NSNumber numberWithInt:2];
  }
  if (!audioQuality) {
    audioQuality = [NSNumber numberWithInt:AVAudioQualityMedium];
  }

  NSDictionary *audioSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                 sampleRate, AVSampleRateKey,
                                 avFormat, AVFormatIDKey,
                                 numberOfChannel, AVNumberOfChannelsKey,
                                 audioQuality, AVEncoderAudioQualityKey,
                                 avLPCMBitDepth, AVLinearPCMBitDepthKey,
                                 avLPCMIsBigEndian, AVLinearPCMIsBigEndianKey,
                                 avLPCMIsFloatKey, AVLinearPCMIsFloatKey,
                                 avLPCMIsNonInterleaved, AVLinearPCMIsNonInterleaved,
                                 nil];

  // Setup audio session
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionAllowBluetooth error:nil];

  // set volume default to speaker
  UInt32 doChangeDefaultRoute = 1;
  AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryDefaultToSpeaker, sizeof(doChangeDefaultRoute), &doChangeDefaultRoute);

  audioRecorder = [[AVAudioRecorder alloc]
                        initWithURL:audioFileURL
                        settings:audioSettings
                        error:nil];
  audioRecorder.meteringEnabled = _meteringEnabled;

  [audioRecorder setDelegate:self];
  [audioRecorder record];
  [self startRecorderTimer];

  NSString *filePath = self->audioFileURL.absoluteString;
  resolve(filePath);
}

RCT_EXPORT_METHOD(stopRecorder:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    if (audioRecorder) {
        [audioRecorder stop];
        if (recordTimer != nil) {
            [recordTimer invalidate];
            recordTimer = nil;
        }

        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        [audioSession setActive:NO error:nil];

        NSString *filePath = audioFileURL.absoluteString;
        resolve(filePath);
    } else {
        reject(@"audioRecorder record", @"audioRecorder is not set", nil);
    }
}

RCT_EXPORT_METHOD(setVolume:(double) volume
                  resolve:(RCTPromiseResolveBlock) resolve
                  reject:(RCTPromiseRejectBlock) reject) {
//    [audioPlayer setVolume: volume];
    resolve(@"setVolume");
}

RCT_EXPORT_METHOD(startPlayer:(NSString*)path
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    NSError *error;
    if ([[path substringToIndex:4] isEqualToString:@"http"]) {
        audioFileURL = [NSURL URLWithString:path];

      NSURLSessionConfiguration *conf = [NSURLSessionConfiguration defaultSessionConfiguration];
      conf.requestCachePolicy = NSURLRequestReturnCacheDataElseLoad;
      NSURLSession *session = [NSURLSession sessionWithConfiguration:conf];
      
        NSURLSessionDataTask *downloadTask = [session
        dataTaskWithURL:audioFileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
//             NSData *data = [NSData dataWithContentsOfURL:audioFileURL];
            if (!vlcPlayer) {
              vlcPlayer = [[VLCMediaPlayer alloc] init];
              vlcPlayer.delegate = self;
            }
            VLCMedia *media = [[VLCMedia alloc] initWithStream:[[NSInputStream alloc] initWithData:data]];
            vlcPlayer.media = media;

            // Able to play in silent mode
            [[AVAudioSession sharedInstance]
                setCategory: AVAudioSessionCategoryPlayback
                error: &error];
            // Able to play in background
            [[AVAudioSession sharedInstance] setActive: YES error: nil];
            dispatch_async(dispatch_get_main_queue(), ^{
              [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
            });
            
            [vlcPlayer play];
            [self startPlayerTimer];
            NSString *filePath = audioFileURL.absoluteString;
            resolve(filePath);
        }];

        [downloadTask resume];
    } else {
        if ([path isEqualToString:@"DEFAULT"]) {
          audioFileURL = [NSURL fileURLWithPath:[GetDirectoryOfType_Sound(NSCachesDirectory) stringByAppendingString:@"sound.m4a"]];
        } else {
            if ([path rangeOfString:@"file://"].location == NSNotFound) {
                audioFileURL = [NSURL fileURLWithPath: [GetDirectoryOfType_Sound(NSCachesDirectory) stringByAppendingString:path]];
            } else {
                NSString *realPath = [path stringByReplacingOccurrencesOfString:@"file://" withString:@""];
                audioFileURL = [NSURL fileURLWithPath:realPath];
            }
        }

        if (!vlcPlayer) {
            RCTLogInfo(@"audio player alloc");
          vlcPlayer = [[VLCMediaPlayer alloc] init];
          vlcPlayer.delegate = self;
        }

        VLCMedia *media = [[VLCMedia alloc] initWithURL:audioFileURL];
        vlcPlayer.media = media;

        // Able to play in silent mode
        [[AVAudioSession sharedInstance]
            setCategory: AVAudioSessionCategoryPlayback
            error: &error];

        NSLog(@"Error %@",error);
        [vlcPlayer play];
        [self startPlayerTimer];

        NSString *filePath = audioFileURL.absoluteString;
        resolve(filePath);
    }
}

RCT_EXPORT_METHOD(resumePlayer: (RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    if (!audioFileURL) {
        reject(@"audioRecorder resume", @"no audioFileURL", nil);
        return;
    }

    if (!vlcPlayer) {
        reject(@"audioRecorder resume", @"no audioPlayer", nil);
        return;
    }

    [[AVAudioSession sharedInstance]
        setCategory: AVAudioSessionCategoryPlayback
        error: nil];
    [vlcPlayer play];
    [self startPlayerTimer];
    NSString *filePath = audioFileURL.absoluteString;
    resolve(filePath);
}

RCT_EXPORT_METHOD(seekToPlayer: (nonnull NSNumber*) time
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    if (vlcPlayer) {
      vlcPlayer.time = [[VLCTime alloc] initWithInt:(time.intValue * 1000)];
        resolve(@"seekTo");
    } else {
        reject(@"audioPlayer seekTo", @"audioPlayer is not set", nil);
    }
}

RCT_EXPORT_METHOD(pausePlayer: (RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    RCTLogInfo(@"pause");
    if (vlcPlayer && [vlcPlayer isPlaying]) {
        [vlcPlayer pause];
        if (playTimer != nil) {
            [playTimer invalidate];
            playTimer = nil;
        }
        resolve(@"pause play");
    } else {
        reject(@"audioPlayer pause", @"audioPlayer is not playing", nil);
    }
}


RCT_EXPORT_METHOD(stopPlayer:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    if (vlcPlayer) {
        if (playTimer != nil) {
            [playTimer invalidate];
            playTimer = nil;
        }
        [vlcPlayer stop];
        vlcPlayer = nil;
        resolve(@"stop play");
    } else {
        reject(@"audioPlayer stop", @"audioPlayer is not set", nil);
    }
}

@end
