# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Poem Searcher, please **do not** open a public GitHub issue. Instead, please report it responsibly by emailing:

**Email**: [1ah.2aw2000@gmail.com](mailto:1ah.2aw2000@gmail.com)

Please include the following information in your report:

- Description of the vulnerability
- Steps to reproduce (if applicable)
- Potential impact
- Suggested fix (if you have one)

### What to Expect

1. **Acknowledgment**: We will acknowledge receipt of your report within 48 hours
2. **Investigation**: We will investigate the vulnerability and determine its severity
3. **Fix**: We will work on a fix and provide you with an estimated timeline
4. **Disclosure**: We will coordinate with you on the timing of public disclosure

## Security Best Practices

### For Users

- **Keep Updated**: Always use the latest version of Poem Searcher
- **Safe Database**: The embedded database file (DB_Poems.db) is read-only by default
- **Local Storage**: All search history and preferences are stored locally on your computer
- **No Network**: Poem Searcher operates entirely offline without internet connectivity

### For Developers

- **Input Validation**: All search queries are properly sanitized before database operations
- **SQLite Injection**: Uses parameterized queries to prevent SQL injection attacks
- **Code Review**: All pull requests are reviewed for security implications
- **Dependencies**: Regular updates of Flutter and Dart dependencies for security patches

## Known Security Considerations

### Local Storage
- User preferences and search history are stored in `shared_preferences`
- This data is stored locally on the Windows system
- No sensitive data is transmitted over the network

### Database Access
- The poetry database uses read-only access patterns
- SQLite PRAGMA statements are configured for safety
- No remote database synchronization

### File System
- The application requires write access to store user preferences
- The bundled database is copied to a user-writable directory on first run
- File permissions follow Windows default security settings

## Security Updates

We take security seriously and will:

1. **Release Patches**: Security fixes will be released as soon as possible
2. **Announce Updates**: Security updates will be announced in release notes
3. **Deprecate Versions**: Older versions will be deprecated if security issues are found

### Supported Versions

| Version | Status | Support Until |
|---------|--------|----------------|
| 1.0.0+ | Current | -  |
| < 1.0.0 | Unsupported | Ended |

## Security Audit

We recommend users review the source code for their own security audits. The codebase is open source and available on GitHub.

## Third-Party Dependencies

We use the following major dependencies:
- **Flutter/Dart**: Official framework with regular security updates
- **SQLite**: Well-tested, widely-used database with strong security record
- **shared_preferences**: Official Flutter plugin with security considerations
- **url_launcher**: Official Flutter plugin with safe URL handling

All dependencies are regularly updated to include security patches.

## Privacy Policy

Poem Searcher:
- ✅ Does NOT collect any user data
- ✅ Does NOT require internet connection
- ✅ Does NOT track user behavior
- ✅ Does NOT share information with third parties
- ✅ Stores all data locally on your computer

## Compliance

- **No personal data collection**: GDPR compliant
- **Local operation only**: No data transmission
- **Open source**: Full code transparency
- **Free and open**: No hidden tracking or analytics

---

## Questions?

For security-related questions or concerns, please reach out to the maintainers at [1ah.2aw2000@gmail.com](mailto:1ah.2aw2000@gmail.com).

Thank you for helping keep Poem Searcher secure! 🔒
