/// One of the three data sources `poem.source_url` is drawn from.
enum Source {
  uqu('https://uqu.edu.sa/App/Poetry/Poems/', 'موسوعة أم القرى'),
  dct('https://poetry.dct.gov.ae/poems/', 'الموسوعة الشعرية'),
  aldiwan('https://www.aldiwan.net/', 'الديوان');

  const Source(this.urlPrefix, this.displayName);

  /// Prefix every `poem.source_url` row from this source starts with.
  final String urlPrefix;

  /// Arabic label shown in the UI.
  final String displayName;

  /// The [Source] whose [urlPrefix] matches [url], or `null` if [url] is
  /// absent or matches none of them.
  static Source? fromUrl(String? url) {
    if (url == null) return null;
    for (final source in Source.values) {
      if (url.startsWith(source.urlPrefix)) return source;
    }
    return null;
  }
}
