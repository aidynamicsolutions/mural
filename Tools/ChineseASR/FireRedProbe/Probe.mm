// Development-only file replay. No microphone, network, learning data, or custom decoder.
// C API ownership follows sherpa-onnx/c-api-examples/fire-red-asr-c-api.c
// (Copyright 2025 Xiaomi Corporation, Apache-2.0), with validation and metrics added.
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <mach/mach.h>
#import <sys/utsname.h>
#include <atomic>
#include <memory>
#include <stdexcept>
#include "sherpa-onnx/c-api/c-api.h"
#include "onnxruntime_c_api.h"

static void Require(bool valid, const char *message) {
    if (!valid) throw std::runtime_error(message);
}

static NSURL *ProbeDirectory(void) {
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    return [documents URLByAppendingPathComponent:@"FireRedProbe" isDirectory:YES];
}

static NSString *Digest(NSURL *url) {
    std::unique_ptr<FILE, decltype(&fclose)> file(fopen(url.fileSystemRepresentation, "rb"), fclose);
    Require(file != nullptr, "Cannot open required local file");
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    unsigned char buffer[65536], digest[CC_SHA256_DIGEST_LENGTH];
    while (true) {
        size_t count = fread(buffer, 1, sizeof(buffer), file.get());
        if (ferror(file.get())) throw std::runtime_error("Cannot finish reading required local file");
        CC_SHA256_Update(&context, buffer, (CC_LONG)count);
        if (count < sizeof(buffer)) break;
    }
    CC_SHA256_Final(digest, &context);
    NSMutableString *hex = [NSMutableString string];
    for (unsigned char byte : digest) [hex appendFormat:@"%02x", byte];
    return hex;
}

static NSDictionary *Memory(void) {
    task_vm_info_data_t info = {};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t status = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
    if (status != KERN_SUCCESS || count < TASK_VM_INFO_REV3_COUNT) {
        return @{@"memory_available": @NO, @"task_info_status": @(status)};
    }
    return @{@"memory_available": @YES, @"footprint_bytes": @(info.phys_footprint),
             @"process_lifetime_peak_footprint_bytes": @(info.ledger_phys_footprint_peak),
             @"process_lifetime_peak_rss_bytes": @(info.resident_size_peak)};
}

@interface ProbeController : UIViewController {
    std::atomic<bool> _stopped;
    std::atomic<int> _warnings;
}
@property(nonatomic) UITextView *statusView;
@property(nonatomic) UIButton *runButton;
@property(nonatomic) UIButton *stopButton;
@property(nonatomic) UIActivityIndicatorView *spinner;
@property(nonatomic) BOOL started;
@property(atomic, copy) NSString *stopReason;
@end

@implementation ProbeController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"FireRed v2 AED probe";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.statusView = [UITextView new];
    self.statusView.editable = NO;
    self.statusView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.statusView.adjustsFontForContentSizeCategory = YES;
    self.statusView.text = @"Local file replay only.\n\nNo microphone or network. Mural is unchanged.\n\nStage the pinned model files in Documents/FireRedProbe/model and a 3-10-second mono 16 kHz PCM16 file as Documents/FireRedProbe/probe.wav.\n\nRuns three replays, releases the recognizer, then reloads for three more. This is not an accuracy qualification.";
    self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.runButton.configuration = UIButtonConfiguration.filledButtonConfiguration;
    [self.runButton setTitle:@"Run file probe" forState:UIControlStateNormal];
    [self.runButton addTarget:self action:@selector(start) forControlEvents:UIControlEventTouchUpInside];
    self.stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.stopButton setTitle:@"Stop probe" forState:UIControlStateNormal];
    [self.stopButton addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
    self.stopButton.enabled = NO;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.statusView, self.spinner, self.runButton, self.stopButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-16],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [self.runButton.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [self.stopButton.heightAnchor constraintGreaterThanOrEqualToConstant:44]
    ]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interrupted)
        name:UIApplicationWillResignActiveNotification object:nil];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--run-firered"]) [self start];
}
- (void)stop {
    self.stopReason = @"Stopped by user";
    _stopped.store(true);
    self.stopButton.enabled = NO;
}
- (void)interrupted {
    if (!self.started) return;
    self.stopReason = @"App became inactive; native work must drain before relaunch";
    _stopped.store(true);
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    _warnings.fetch_add(1);
    self.stopReason = @"Memory warning; qualification blocked";
    _stopped.store(true);
    [@"Memory warning received. Do not retry inference.\n" writeToURL:[ProbeDirectory() URLByAppendingPathComponent:@"memory-warning.txt"]
        atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
- (void)show:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusView.text = [self.statusView.text stringByAppendingFormat:@"\n%@", message];
    });
}
- (void)checkpoint:(NSString *)stage report:(NSMutableDictionary *)report url:(NSURL *)url {
    NSMutableDictionary *event = [Memory() mutableCopy];
    event[@"stage"] = stage;
    event[@"uptime_seconds"] = @(NSProcessInfo.processInfo.systemUptime);
    event[@"thermal_state"] = @(NSProcessInfo.processInfo.thermalState);
    event[@"memory_warnings"] = @(_warnings.load());
    [report[@"events"] addObject:event];
    report[@"stage"] = stage;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
    Require(data != nil && [data writeToURL:url options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:&error],
            "Cannot save private checkpoint; stopped");
    [self show:stage];
}
- (void)checkStop {
    Require(!_stopped.load(), "Stopped; native handles released after work returned");
    Require(NSProcessInfo.processInfo.thermalState < NSProcessInfoThermalStateSerious,
            "Serious or critical thermal state; qualification blocked");
}
- (void)start {
    if (self.started) return; // One run per process; fresh-process peaks remain interpretable.
    self.started = YES;
    self.runButton.enabled = NO;
    self.stopButton.enabled = YES;
    [self.spinner startAnimating];
    self.statusView.text = @"Starting FireRedASR2-AED. Keep the app foregrounded.\nStop never frees handles during synchronous inference.\n";
    // Exactly one worker owns every C handle. UI cancellation only sets an atomic flag.
    dispatch_async(dispatch_queue_create("mural.firered.file-replay", DISPATCH_QUEUE_SERIAL), ^{
        @autoreleasepool { [self replay]; }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            self.stopButton.enabled = NO;
        });
    });
}
- (void)replay {
    NSURL *documents = ProbeDirectory();
    NSURL *reportURL = [documents URLByAppendingPathComponent:[NSString stringWithFormat:@"firered-%@.json", NSUUID.UUID.UUIDString]];
    NSMutableDictionary *report = [@{@"schema": @"mural.firered.file-probe.v1", @"complete": @NO,
        @"events": [NSMutableArray new], @"predictions": [NSMutableArray new],
        @"provider": @"cpu", @"threads": @1, @"batch_size": @1, @"decoding": @"greedy_search",
        @"sherpa_version": @(SherpaOnnxGetVersionStr()),
        @"ort_version": @(OrtGetApiBase()->GetVersionString()),
        @"os": NSProcessInfo.processInfo.operatingSystemVersionString} mutableCopy];
    struct utsname device;
    if (uname(&device) == 0) report[@"hardware"] = @(device.machine);
    try {
        NSError *error = nil;
        Require([NSFileManager.defaultManager createDirectoryAtURL:documents withIntermediateDirectories:YES attributes:nil error:&error],
                "Cannot create isolated probe directory");
        Require([documents setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&error], "Cannot exclude probe files from backup");
        [self checkpoint:@"Validating local assets" report:report url:reportURL];
        Require([Memory()[@"memory_available"] boolValue], "Native footprint measurement unavailable");
        NSURL *pinURL = [NSBundle.mainBundle URLForResource:@"pin" withExtension:@"json"];
        if (!pinURL) throw std::runtime_error("Missing built-in model pin");
        NSData *pinData = [NSData dataWithContentsOfURL:pinURL];
        if (!pinData) throw std::runtime_error("Unreadable built-in model pin");
        NSDictionary *pin = [NSJSONSerialization JSONObjectWithData:pinData options:0 error:&error];
        Require([pin[@"artifacts"] count] == 3, "Invalid built-in model pin");
        report[@"pin"] = pin;
        Require([report[@"sherpa_version"] isEqual:pin[@"sherpa_version"]] &&
                [report[@"ort_version"] isEqual:pin[@"ort_version"]], "Runtime version mismatch");
        NSURL *model = [documents URLByAppendingPathComponent:@"model" isDirectory:YES];
        NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
        for (NSString *name in pin[@"artifacts"]) {
            [self checkStop];
            NSURL *file = [model URLByAppendingPathComponent:name];
            NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:&error];
            Require([attributes[NSFileType] isEqual:NSFileTypeRegular] &&
                [attributes[NSFileSize] isEqual:pin[@"artifacts"][name][@"bytes"]], "Missing or wrong-sized pinned model file");
            Require([Digest(file) isEqual:pin[@"artifacts"][name][@"sha256"]], "Model hash mismatch; no fallback");
        }
        report[@"verification_seconds"] = @(NSProcessInfo.processInfo.systemUptime - start);
        NSURL *wavURL = [documents URLByAppendingPathComponent:@"probe.wav"];
        NSDictionary *wavAttributes = [NSFileManager.defaultManager attributesOfItemAtPath:wavURL.path error:&error];
        Require([wavAttributes[NSFileType] isEqual:NSFileTypeRegular] &&
            [wavAttributes[NSFileSize] unsignedLongLongValue] <= 1024 * 1024, "Missing or oversized probe.wav");
        AVAudioFile *audio = [[AVAudioFile alloc] initForReading:wavURL error:&error];
        Require(audio && audio.fileFormat.channelCount == 1 && audio.fileFormat.sampleRate == 16000 &&
            audio.fileFormat.commonFormat == AVAudioPCMFormatInt16 && audio.length >= 48000 && audio.length <= 160000,
            "Require 3-10-second mono 16 kHz PCM16 WAV");
        std::unique_ptr<const SherpaOnnxWave, decltype(&SherpaOnnxFreeWave)> wave(
            SherpaOnnxReadWave(wavURL.fileSystemRepresentation), SherpaOnnxFreeWave);
        Require(wave && wave->sample_rate == 16000 && wave->num_samples == audio.length, "Cannot read complete WAV");
        report[@"audio_sha256"] = Digest(wavURL);
        report[@"audio_seconds"] = @(wave->num_samples / 16000.0);
        // Keep UTF8String storage alive through both recognizer creations under ARC.
        __attribute__((objc_precise_lifetime)) NSString *encoder = [model URLByAppendingPathComponent:@"encoder.int8.onnx"].path;
        __attribute__((objc_precise_lifetime)) NSString *decoder = [model URLByAppendingPathComponent:@"decoder.int8.onnx"].path;
        __attribute__((objc_precise_lifetime)) NSString *tokens = [model URLByAppendingPathComponent:@"tokens.txt"].path;
        SherpaOnnxOfflineRecognizerConfig config = {};
        config.feat_config.sample_rate = 16000;
        config.feat_config.feature_dim = 80;
        config.model_config.fire_red_asr.encoder = encoder.UTF8String;
        config.model_config.fire_red_asr.decoder = decoder.UTF8String;
        config.model_config.tokens = tokens.UTF8String;
        config.model_config.provider = "cpu";
        config.model_config.num_threads = 1;
        config.decoding_method = "greedy_search";
        NSString *firstText = nil;
        for (int cycle = 0; cycle < 2; ++cycle) {
            [self checkStop];
            [self checkpoint:[NSString stringWithFormat:@"Loading cycle %d", cycle + 1] report:report url:reportURL];
            start = NSProcessInfo.processInfo.systemUptime;
            std::unique_ptr<const SherpaOnnxOfflineRecognizer, decltype(&SherpaOnnxDestroyOfflineRecognizer)> recognizer(
                SherpaOnnxCreateOfflineRecognizer(&config), SherpaOnnxDestroyOfflineRecognizer);
            Require(recognizer != nullptr, "Native recognizer creation failed");
            NSTimeInterval prepareSeconds = NSProcessInfo.processInfo.systemUptime - start;
            report[[NSString stringWithFormat:@"prepare_%d_seconds", cycle + 1]] = @(prepareSeconds);
            [self checkStop];
            Require(prepareSeconds <= 60, "Preparation exceeded 60-second probe stop bound");
            for (int turn = 0; turn < 3; ++turn) {
                [self checkStop];
                [self checkpoint:[NSString stringWithFormat:@"Decoding cycle %d turn %d", cycle + 1, turn + 1] report:report url:reportURL];
                start = NSProcessInfo.processInfo.systemUptime;
                {
                    std::unique_ptr<const SherpaOnnxOfflineStream, decltype(&SherpaOnnxDestroyOfflineStream)> stream(
                        SherpaOnnxCreateOfflineStream(recognizer.get()), SherpaOnnxDestroyOfflineStream);
                    Require(stream != nullptr, "Native stream creation failed");
                    SherpaOnnxAcceptWaveformOffline(stream.get(), 16000, wave->samples, wave->num_samples);
                    SherpaOnnxDecodeOfflineStream(recognizer.get(), stream.get());
                    [self checkStop];
                    std::unique_ptr<const SherpaOnnxOfflineRecognizerResult, decltype(&SherpaOnnxDestroyOfflineRecognizerResult)> result(
                        SherpaOnnxGetOfflineStreamResult(stream.get()), SherpaOnnxDestroyOfflineRecognizerResult);
                    Require(result && result->text, "Native result missing");
                    NSString *text = [NSString stringWithUTF8String:result->text];
                    Require(text.length > 0, "Empty or invalid native result");
                    if (!firstText) firstText = text;
                    Require([text isEqual:firstText], "Repeated replay changed raw output");
                    NSTimeInterval seconds = NSProcessInfo.processInfo.systemUptime - start;
                    [report[@"predictions"] addObject:@{@"cycle": @(cycle + 1), @"turn": @(turn + 1),
                        @"text": text, @"decode_seconds": @(seconds)}];
                    Require(seconds <= 60, "Decode exceeded 60-second probe stop bound");
                } // Result and stream destroyed only after synchronous decode returns.
                [self checkpoint:@"Result and stream released" report:report url:reportURL];
            }
            recognizer.reset();
            [self checkpoint:@"Recognizer released" report:report url:reportURL];
        }
        wave.reset();
        [self checkStop];
        report[@"complete"] = @YES;
        [self checkpoint:@"Replay complete; all native handles released" report:report url:reportURL];
        [self show:[@"Raw output: " stringByAppendingString:firstText]];
    } catch (const std::exception &error) {
        report[@"complete"] = @NO;
        report[@"failure"] = self.stopReason ?: @(error.what());
        try { [self checkpoint:@"Blocked; native handles drained" report:report url:reportURL]; } catch (...) {}
        [self show:report[@"failure"]];
    }
    [self show:@"Keep the private report. Relaunch for a fresh-process run; do not retry a resource failure."];
}
@end

#if MURAL_FIRERED_EMBEDDED
#import "Probe.h"
UIViewController *MuralFireRedProbeViewController(void) {
    return [[UINavigationController alloc] initWithRootViewController:[ProbeController new]];
}
#else
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic) UIWindow *window;
@end
@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[ProbeController new]];
    [self.window makeKeyAndVisible];
}
@end
@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation AppDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Probe" sessionRole:session.role];
    configuration.delegateClass = SceneDelegate.class;
    return configuration;
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class)); }
}
#endif
