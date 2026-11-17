# YA7 0.2.10 validation

Version 0.2.10, build 12, macOS 14+, Universal arm64/x86_64. Bundled 7-Zip remains 26.05. English and German remain supported, with English fallback.

- All 33 local Xcode tests passed with zero failures for this code. Regression coverage includes context targets, real archive contents, background directory reading, a 1,000-file directory, navigation races, every sort column, search selection semantics, cached selection statistics and rapid listing changes.
- Universal Developer ID build passed. Apple notarization Accepted without findings, submission `ab261a2b-85b8-473c-9d26-e1cf766de5ea`. Ticket stapled and validated; Gatekeeper accepted the DMG and contained app.
- Read-only DMG payload matched the signed export. App and extension versions, English/German resources, icon, Applications link and license material were checked.
- The prior user-assisted Finder creation test was performed with 0.2.9. No fresh Finder end-to-end or second-Mac installation test was performed for 0.2.10. The installed app has not been replaced.

## Performance evidence

Optimized synthetic measurements use the same input lists as the earlier benchmark; these are derived-data timings, not complete UI render/frame measurements. Repeated reads are medians of five iterations.

| Entries | Earlier repeated filter/sort/selection pass | Prepared-result read |
| --- | --- | --- |
| 1,000 | 29 ms | < 0.01 ms |
| 10,000 | 223 ms | < 0.01 ms |
| 50,000 | 1,252 ms | < 0.01 ms |

Sorting still costs time when inputs change. Initial background preparation was about 29 / 258 / 1,942 ms respectively (single observations); the input setters took about 0.17 / 0.59 / 3.01 ms. A fresh query reused the sorting result and took about 2.2 / 10.4 / 89.6 ms, including background work. Results were checked against the previous filter-and-sort expression. No Instruments CPU, memory or frame-rate capture was made.
