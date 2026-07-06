/// One of the data sources a poem is drawn from.
///
/// The three web encyclopedias are identified by their `poem.source_url`
/// prefix; [moktoum] (imported poems) has no URL. Every poem is classified by
/// the stored `poem.source_name` column ([displayName]), so filtering no longer
/// depends on the URL.
enum Source {
  uqu('https://uqu.edu.sa/App/Poetry/Poems/', 'موسوعة أم القرى'),
  dct('https://poetry.dct.gov.ae/poems/', 'الموسوعة الشعرية'),
  aldiwan('https://www.aldiwan.net/', 'الديوان'),
  moktoum(null, 'موسوعة آل مكتوم');

  const Source(this.urlPrefix, this.displayName);

  /// Prefix every `poem.source_url` row from this source starts with, or `null`
  /// for sources whose poems carry no URL (see [moktoum]).
  final String? urlPrefix;

  /// Arabic label shown in the UI, and the value stored in `poem.source_name`.
  final String displayName;

  /// The [Source] whose [urlPrefix] matches [url], or `null` if [url] is
  /// absent or matches none of them. Only sources with a [urlPrefix] are tried.
  static Source? fromUrl(String? url) {
    if (url == null) return null;
    for (final source in Source.values) {
      final prefix = source.urlPrefix;
      if (prefix != null && url.startsWith(prefix)) return source;
    }
    return null;
  }

  /// The [Source] whose [displayName] equals the stored `poem.source_name`
  /// [name], or `null` if absent/unrecognized.
  static Source? fromName(String? name) {
    if (name == null) return null;
    for (final source in Source.values) {
      if (source.displayName == name) return source;
    }
    return null;
  }
}
