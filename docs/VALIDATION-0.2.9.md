# YA7 0.2.9 validation

Finder output handoff correction. Apple documents staging Action Extension output in the system item replacement directory: https://developer.apple.com/documentation/appkit/add-functionality-to-finder-with-action-extensions

Previously YA7 staged output in its generic temporary directory. The updated implementation uses FileManager.itemReplacementDirectory and shares the provider implementation with its regression test. Original providers and files remain unchanged. Output is retained for Finder to consume after extension completion.

23 Xcode tests passed with zero failures, including real ZIP creation, extraction, provider consumption and input preservation. Universal Developer ID build passed.

These tests exercise provider handoff, not Finder's final placement. Direct Finder verification after Done is still required. This correction does not install or replace the user's existing app.
