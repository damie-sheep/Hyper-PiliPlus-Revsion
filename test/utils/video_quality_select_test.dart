import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter_test/flutter_test.dart';

PlayUrlModel _playUrl(List<VideoQuality> videoIds) => PlayUrlModel.fromJson({
  'dash': {
    'duration': 0,
    'video': [
      for (final id in videoIds)
        {
          'id': id.code,
          'codecs': VideoDecodeFormatType.AV1.codes.first,
        },
    ],
  },
  'accept_quality': [
    for (final id in videoIds) id.code,
  ],
  'support_formats': [
    for (final id in videoIds)
      {
        'quality': id.code,
        'codecs': VideoDecodeFormatType.AV1.codes,
      },
  ],
});

void main() {
  test(
    'unrelated missing quality does not block an available preferred stream',
    () {
      final data = _playUrl([VideoQuality.dolbyVision, VideoQuality.high1080]);
      data.acceptQuality!.add(VideoQuality.clear480.code);
      data.supportFormats!.add(
        FormatItem.fromJson({
          'quality': VideoQuality.clear480.code,
          'codecs': VideoDecodeFormatType.AV1.codes,
        }),
      );
      expect(data.missingVideoQualityBelowHighest, VideoQuality.clear480.code);
      expect(
        VideoUtils.needsInitialQualitySupplement(
          data,
          VideoQuality.high1080.code,
          [.AV1],
        ),
        isFalse,
      );
      expect(
        VideoUtils.needsInitialQualitySupplement(
          data,
          VideoQuality.clear480.code,
          [.AV1],
        ),
        isTrue,
      );
    },
  );

  test('missing preferred codec keeps the initial supplement', () {
    final data = _playUrl([VideoQuality.dolbyVision, VideoQuality.high1080]);
    data.supportFormats!.add(
      FormatItem.fromJson({
        'quality': VideoQuality.clear480.code,
        'codecs': VideoDecodeFormatType.AV1.codes,
      }),
    );
    data.supportFormats!
        .firstWhere((f) => f.quality == VideoQuality.high1080.code)
        .codecs = [
      ...VideoDecodeFormatType.AVC.codes,
      ...VideoDecodeFormatType.AV1.codes,
    ];
    expect(
      VideoUtils.needsInitialQualitySupplement(
        data,
        VideoQuality.high1080.code,
        [.AVC, .AV1],
      ),
      isTrue,
    );
  });

  test('find target quality', () {
    final playUrl = _playUrl(VideoQuality.values);
    final dash = playUrl.dash!;
    final preferQa = VideoQuality.high1080.code;
    final (
      int targetQuality,
      FormatItem targetFormat,
      VideoDecodeFormatType targetDecode,
      VideoItem targetVideo,
    ) = VideoUtils.findTargetVideo(
      dash.video!,
      preferQa,
      playUrl.acceptQuality,
      playUrl.supportFormats!,
      [.AV1],
    );
    expect(targetQuality, preferQa);
  });

  test('find closest quality', () {
    final playUrl = _playUrl(
      VideoQuality.values.toList()..remove(VideoQuality.high1080plus),
    );
    final dash = playUrl.dash!;
    final preferQa = VideoQuality.high1080plus.code;
    final (
      int targetQuality,
      FormatItem targetFormat,
      VideoDecodeFormatType targetDecode,
      VideoItem targetVideo,
    ) = VideoUtils.findTargetVideo(
      dash.video!,
      preferQa,
      playUrl.acceptQuality,
      playUrl.supportFormats!,
      [.AV1],
    );
    expect(targetQuality, VideoQuality.superResolution.code);
  });

  test('find closest quality', () {
    final playUrl = _playUrl([
      VideoQuality.dolbyVision,
      VideoQuality.high1080,
      VideoQuality.clear480,
    ]);
    final dash = playUrl.dash!;
    final preferQa = VideoQuality.speed240.code;
    final (
      int targetQuality,
      FormatItem targetFormat,
      VideoDecodeFormatType targetDecode,
      VideoItem targetVideo,
    ) = VideoUtils.findTargetVideo(
      dash.video!,
      preferQa,
      playUrl.acceptQuality,
      playUrl.supportFormats!,
      [.AV1],
    );
    expect(targetQuality, VideoQuality.clear480.code);
  });
}
