/// How a video should be handed to the platform player.
enum VideoSourceType { contentUri, file, network }

class VideoSource {
  const VideoSource({required this.type, required this.uri});

  final VideoSourceType type;
  final Uri uri;
}

/// Resolves the URL returned by `AssetEntity.getMediaUrl()` into something
/// `video_player` can open.
///
/// Android returns a `content://` URI, which must be played as a content URI
/// rather than a file. iOS returns a `file://` URL. Other URLs are played as
/// network sources.
VideoSource? resolveVideoSource({
  required String? mediaUrl,
  required bool isAndroid,
}) {
  if (mediaUrl == null || mediaUrl.isEmpty) return null;

  final uri = Uri.tryParse(mediaUrl);

  if (uri == null) return null;

  switch (uri.scheme) {
    case 'content':
      if (!isAndroid) return null;
      return VideoSource(type: VideoSourceType.contentUri, uri: uri);
    case 'file':
      return VideoSource(type: VideoSourceType.file, uri: uri);
    case 'http':
    case 'https':
      return VideoSource(type: VideoSourceType.network, uri: uri);
    default:
      return null;
  }
}
