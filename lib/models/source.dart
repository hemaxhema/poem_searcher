/// One of the data sources a poem is drawn from.
///
/// The three web encyclopedias are identified by their `poem.source_url`
/// prefix; [moktoum] (imported poems) has no URL. Every poem is classified by
/// the stored `poem.source_id` column (this enum's index), so filtering no
/// longer depends on the URL. `poem.source_id`/`poem_alias.source_id`
/// `REFERENCES` a `source` lookup table whose `id`s are fixed to match this
/// enum's index (see `tool/normalize_metadata.dart`).
enum Source {
  uqu('https://uqu.edu.sa/App/Poetry/Poems/', 'موسوعة أم القرى'),
  dct('https://poetry.dct.gov.ae/poems/', 'الموسوعة الشعرية'),
  aldiwan('https://www.aldiwan.net/', 'الديوان'),
  moktoum(null, 'موسوعة آل مكتوم');

  const Source(this.urlPrefix, this.displayName);

  /// Prefix stripped from every `poem.source_url` row from this source before
  /// storage (so `poem.source_url` holds only the per-source suffix); `null`
  /// for sources whose poems carry no URL (see [moktoum]). The app expands a
  /// stored suffix back to a full URL by re-prepending this prefix.
  final String? urlPrefix;

  /// Arabic label shown in the UI, derived from the stored `poem.source_id`
  /// (this enum's index).
  final String displayName;

  /// The [Source] whose [urlPrefix] is a prefix of [url], or `null` if [url]
  /// is absent or matches none of them. Only sources with a [urlPrefix] are
  /// tried. For a *full* URL (not a stored suffix) — e.g. one pasted by a user.
  static Source? fromUrl(String? url) {
    if (url == null) return null;
    for (final source in Source.values) {
      final prefix = source.urlPrefix;
      if (prefix != null && url.startsWith(prefix)) return source;
    }
    return null;
  }

  /// The [Source] whose [displayName] equals [name], or `null` if
  /// absent/unrecognized.
  static Source? fromName(String? name) {
    if (name == null) return null;
    for (final source in Source.values) {
      if (source.displayName == name) return source;
    }
    return null;
  }
}
