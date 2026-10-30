# Privacy

YA7 processes archives on your Mac. It has no analytics or crash-upload SDK. Preferences and successful 7-Zip version-check results are stored locally in macOS UserDefaults. Archive passwords are passed to 7-Zip over stdin and are not intentionally persisted by YA7.

The **weekly 7-Zip version check** is enabled by default and can be disabled in Settings. A manual check remains available. It requests `https://api.github.com/repos/ip7z/7zip/releases/latest` over HTTPS; GitHub receives ordinary connection metadata, including your IP address and the fixed YA7 version-check User-Agent. YA7 does not attach archive contents, file names, passwords or archive paths. Opening a release link launches your browser and is subject to GitHub's privacy terms. No separate background daemon runs when YA7 is closed; no engine update is installed automatically.

Extraction uses temporary files. Intermediate TAR data is removed after success/error/cancellation. Successful Finder output is retained temporarily so Finder can import it; its cleanup lifecycle is a known limitation. Do not use confidential archives as issue attachments. System logs, OS-managed memory/swap and third-party operating-system services are outside a promise of zero persistence.
