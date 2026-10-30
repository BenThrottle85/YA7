# YA7 0.2.9 validation

Finder output handoff correction. Apple documents staging Action Extension output in the system item replacement directory: https://developer.apple.com/documentation/appkit/add-functionality-to-finder-with-action-extensions

Previously YA7 staged output in its generic temporary directory. The updated implementation uses FileManager.itemReplacementDirectory and shares the provider implementation with its regression test. Original providers and files remain unchanged. Output is retained for Finder to consume after extension completion.

23 Xcode tests passed with zero failures, including real ZIP creation, extraction, provider consumption and input preservation. Universal Developer ID build passed.

YA7 0.2.9 (build 11) was subsequently installed in Applications at the user's request. The registered Finder pack extension was verified as 0.2.9. The user performed Create → Done and confirmed the resulting YA7-Test.7z appeared beside YA7-Test.txt. Automated checks confirmed the archive exists, passes 7-Zip integrity testing and contains byte-identical original content; the original file is unchanged. Direct Finder interaction was performed by the user because no desktop UI control tool was available. This validates the 7z case on this Mac; extraction, ZIP and second-Mac runtime checks remain separate.
