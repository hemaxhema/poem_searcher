# Contributing to Poem Searcher

Thank you for your interest in contributing to Poem Searcher! We welcome contributions from everyone, whether it's reporting bugs, suggesting features, or submitting code improvements.

## Code of Conduct

This project and everyone participating in it is governed by our Code of Conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the [issue list](https://github.com/yourusername/poem_searcher/issues) as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps which reproduce the problem**
- **Provide specific examples to demonstrate the steps**
- **Describe the behavior you observed after following the steps**
- **Explain which behavior you expected to see instead and why**
- **Include screenshots and animated GIFs if possible**
- **Include your environment details** (Windows version, Flutter version, etc.)

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

- **Use a clear and descriptive title** starting with [FEATURE REQUEST]
- **Provide a step-by-step description of the suggested enhancement**
- **Provide specific examples to demonstrate the steps**
- **Describe the current behavior and expected behavior**
- **Explain why this enhancement would be useful**
- **List some other applications where this enhancement exists, if applicable**

### Pull Requests

- Fill in the required template
- Follow the Dart/Flutter style guides
- End all files with a newline
- Include appropriate test cases
- Update documentation as needed
- Follow the existing code style

## Development Setup

### Prerequisites
- Flutter SDK 3.11.5 or higher
- Dart SDK (comes with Flutter)
- Windows 10 or later
- Visual Studio or Visual Studio Build Tools (for Windows development)

### Local Development

1. **Fork and clone the repository**
   ```bash
   git clone https://github.com/yourusername/poem_searcher.git
   cd poem_searcher
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Create a branch for your feature**
   ```bash
   git checkout -b feature/your-feature-name
   ```

4. **Make your changes**
   - Write clean, well-commented code
   - Follow Dart style guide
   - Run `flutter analyze` to check for issues
   - Run `flutter format` to format code

5. **Test your changes**
   ```bash
   flutter test
   ```

6. **Build and test the application**
   ```bash
   flutter build windows --debug
   flutter run -d windows
   ```

## Style Guides

### Dart/Flutter Code Style

- Follow the [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)
- Use meaningful variable and function names
- Keep functions small and focused
- Add comments for complex logic
- Write tests for new functionality

### Commit Messages

- Use the present tense ("Add feature" not "Added feature")
- Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit the first line to 72 characters or less
- Reference issues and pull requests liberally after the first line

Example:
```
Add tashkeel-aware search functionality

- Implement text normalization for diacritical marks
- Add unit tests for search logic
- Update documentation

Closes #42
```

### Documentation

- Use clear, descriptive language
- Keep documentation up-to-date with code changes
- Add examples for complex features
- Include code blocks with syntax highlighting

## Testing Guidelines

### Writing Tests

- Write tests for all new features
- Ensure existing tests still pass
- Aim for good code coverage
- Use descriptive test names

```dart
void main() {
  group('Search functionality', () {
    test('should find poems with tashkeel-aware search', () {
      expect(searchPoems('علي', true), isNotEmpty);
    });
  });
}
```

### Running Tests

```bash
# Run all tests
flutter test

# Run tests with coverage
flutter test --coverage

# Run specific test file
flutter test test/db/poem_repository_test.dart
```

## Review Process

1. **Automated Checks**
   - Code analysis must pass: `flutter analyze`
   - Tests must pass: `flutter test`
   - Code must be formatted: `flutter format`

2. **Code Review**
   - At least one maintainer review required
   - Changes may be requested
   - Once approved, PR can be merged

3. **Merge**
   - Squash commits for cleaner history
   - Use descriptive merge commit message
   - Delete branch after merge

## Questions?

- **Documentation**: Check [README.md](README.md)
- **Issues**: Search [GitHub Issues](https://github.com/yourusername/poem_searcher/issues)
- **Discussions**: Check [GitHub Discussions](https://github.com/yourusername/poem_searcher/discussions)

## License

By contributing to Poem Searcher, you agree that your contributions will be licensed under its MIT License.

---

Thank you for contributing! Your efforts help make Poem Searcher better for everyone. 🙏
