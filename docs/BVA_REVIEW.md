# Squeaky boundary value analysis

Review date: 2026-10-31. Scope: first-party Swift implementation, app flows, scanner integration, resource loading, and baseline build/packaging scripts. Vendored libyara was exercised through its Swift boundary; this is not a line-by-line audit or fuzzing certification of the entire C dependency.

The review found defects affecting deletion safety, stale duplicates, app identifiers, asynchronous state, protection coverage reporting, subprocesses, and empty/invalid inputs. Fixes are separate commits. No real applications, user downloads, startup agents, or snapshots were removed during validation. Removal fixtures live in unique directories under `.build`; other fixtures use temporary directories.

## Evidence and execution

The matrix has **207 individual boundary items**: **142 exercised by automated tests**, **55 inspected statically**, and **10 requiring further/live validation**. A test method can exercise multiple inputs. Static rows describe control flow inspected in source, not a claim that the behavior was observed on a live system. Not-executed rows are explicit limits on this review.

Run tests from the repository root:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/squeaky-clang-cache swift test --disable-sandbox --build-system native
```

The cache override avoids the restricted user cache location in this workspace. The first run without that override failed before compilation. Fixtures were corrected for the host's case-insensitive filesystem; the duplicate fixture exposed and led to fixing `/var` versus `/private/var` path matching.

Final validation on Apple Silicon: **19 XCTest methods passed with zero failures in both debug and release configurations**. The release run rebuilt the app and vendored C dependency in a separate scratch directory:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/squeaky-clang-cache swift test -c release --scratch-path /tmp/squeaky-review-release --disable-sandbox --build-system native
```

`git diff --check` passed. The matrix row count and evidence totals were checked programmatically. The toolchain emitted cache/sandbox and deprecated-backend warnings; both final runs completed successfully. No installer signing, keychain mutation, real snapshot deletion, or permission grant was performed.

## Fix commits

Each fix was committed after the debug regression suite passed. The input-only relaunch and geometry changes have build/static validation; their live UI behavior remains in the matrix.

| Commit | Change |
| --- | --- |
| `cd3d69a` | validate removal paths through resolved ancestors |
| `47b46e4` | reject incomplete hashes on file read errors |
| `dd3e056` | preserve extras on failed removal and count actual deletions |
| `2a69f3e` | only strip valid host UUIDs from app identifiers |
| `ac70489` | ignore superseded scan completions |
| `f9c709b` | require path boundaries when attaching threat launch items |
| `f90d710` | report incomplete protection scans instead of clean results |
| `93da82b` | handle CPU counter resets and cancelled samples |
| `71ccc75` | close failed Gatekeeper database handles |
| `a84bf0a` | drain subprocess output streams concurrently |
| `02e8962` | require review before removing partial downloads |
| `6712fce` | revalidate duplicates before removal and stabilize keeper selection |
| `ec641c1` | bound snapshot dimensions and debug delay inputs |
| `205fd16` | handle empty icon fillers and collapsed artwork geometry |
| `677d37a` | propagate cancellation to parallel protection workers |
| `0559a68` | keep current app open when permission relaunch fails |
| `47cf867` | serialize module removals and preserve busy state |
| `a135bbd` | surface incomplete Gatekeeper blocklist reads |

## Boundary matrix

| ID | Area | Boundary input or state | Expected behavior or validation need | Evidence status | Evidence |
| --- | --- | --- | --- | --- | --- |
| BVA-001 | Removal | Remove home itself | Refused | Tested | FileSafetyTests |
| BVA-002 | Removal | Remove home/Library | Refused | Tested | FileSafetyTests |
| BVA-003 | Removal | Remove home/Desktop | Refused | Tested | FileSafetyTests |
| BVA-004 | Removal | Remove home/Documents | Refused | Tested | FileSafetyTests |
| BVA-005 | Removal | Remove home/Downloads | Refused | Tested | FileSafetyTests |
| BVA-006 | Removal | Remove home/Movies | Refused | Tested | FileSafetyTests |
| BVA-007 | Removal | Remove home/Music | Refused | Tested | FileSafetyTests |
| BVA-008 | Removal | Remove home/Pictures | Refused | Tested | FileSafetyTests |
| BVA-009 | Removal | Remove home/Applications | Refused | Tested | FileSafetyTests |
| BVA-010 | Removal | Remove home/.Trash | Refused | Tested | FileSafetyTests |
| BVA-011 | Removal | Remove home/Library/Caches | Refused | Tested | FileSafetyTests |
| BVA-012 | Removal | Remove home/Library/Logs | Refused | Tested | FileSafetyTests |
| BVA-013 | Removal | Remove home/Library/Application Support | Refused | Tested | FileSafetyTests |
| BVA-014 | Removal | Remove home/Library/Preferences | Refused | Tested | FileSafetyTests |
| BVA-015 | Removal | Remove home/Library/Containers | Refused | Tested | FileSafetyTests |
| BVA-016 | Removal | Remove home/Library/Group Containers | Refused | Tested | FileSafetyTests |
| BVA-017 | Removal | Remove home/Library/Mail | Refused | Tested | FileSafetyTests |
| BVA-018 | Removal | Regular child of Documents | Allowed | Tested | FileSafetyTests |
| BVA-019 | Removal | Sibling outside home | Refused | Tested | FileSafetyTests |
| BVA-020 | Removal | Final symlink to outside | Link itself may be removed | Tested | FileSafetyTests |
| BVA-021 | Removal | Child under symlink to outside | Refused | Tested | FileSafetyTests |
| BVA-022 | Removal | Protected folder through home alias | Refused | Tested | FileSafetyTests |
| BVA-023 | Removal | HTTPS URL | Refused | Tested | FileSafetyTests |
| BVA-024 | Removal | Top-level Applications app | Allowed | Tested | FileSafetyTests |
| BVA-025 | Removal | Helper app inside another app | Refused | Tested | FileSafetyTests |
| BVA-026 | Hashing | Missing hash input | nil | Tested | HashTests |
| BVA-027 | Hashing | Directory read error | nil, never empty-content hash | Tested | HashTests |
| BVA-028 | Hashing | Negative byte limit | nil | Tested | HashTests |
| BVA-029 | Hashing | Known abc input | Known SHA256 digest | Tested | HashTests |
| BVA-030 | Hashing | Zero byte limit | Empty-content SHA256 digest | Tested | HashTests |
| BVA-031 | Hashing | 0 bytes with exact-length limit | Matches unlimited digest | Tested | HashTests |
| BVA-032 | Hashing | 0 bytes with limit one beyond EOF | Matches unlimited digest | Tested | HashTests |
| BVA-033 | Hashing | 1 bytes with exact-length limit | Matches unlimited digest | Tested | HashTests |
| BVA-034 | Hashing | 1 bytes with limit one beyond EOF | Matches unlimited digest | Tested | HashTests |
| BVA-035 | Hashing | 65535 bytes with exact-length limit | Matches unlimited digest | Tested | HashTests |
| BVA-036 | Hashing | 65535 bytes with limit one beyond EOF | Matches unlimited digest | Tested | HashTests |
| BVA-037 | Hashing | 65536 bytes with exact-length limit | Matches unlimited digest | Tested | HashTests |
| BVA-038 | Hashing | 65536 bytes with limit one beyond EOF | Matches unlimited digest | Tested | HashTests |
| BVA-039 | Hashing | 65537 bytes with exact-length limit | Matches unlimited digest | Tested | HashTests |
| BVA-040 | Hashing | 65537 bytes with limit one beyond EOF | Matches unlimited digest | Tested | HashTests |
| BVA-041 | Hashing | 1048575 bytes with exact-length limit | Matches unlimited digest | Tested | HashTests |
| BVA-042 | Hashing | 1048575 bytes with limit one beyond EOF | Matches unlimited digest | Tested | HashTests |
| BVA-043 | Hashing | 1048576 bytes with exact-length limit | Matches unlimited digest | Tested | HashTests |
| BVA-044 | Hashing | 1048576 bytes with limit one beyond EOF | Matches unlimited digest | Tested | HashTests |
| BVA-045 | Hashing | 1048577 bytes with exact-length limit | Matches unlimited digest | Tested | HashTests |
| BVA-046 | Hashing | 1048577 bytes with limit one beyond EOF | Matches unlimited digest | Tested | HashTests |
| BVA-047 | Removal execution | Refused primary with existing extra | Extra retained; zero removed and bytes | Tested | RemovalTests |
| BVA-048 | Removal execution | Missing primary with existing extra | Extra retained; failure reported | Tested | RemovalTests |
| BVA-049 | Removal execution | Cancel before first request | No removal; cancelled true | Tested | RemovalTests |
| BVA-050 | Removal execution | Same request twice | One removal and one removed URL | Tested | RemovalTests |
| BVA-051 | Removal execution | Empty request list | Zero removed | Tested | RemovalTests |
| BVA-052 | App matching | ByHost identifier ending in cafe | Preserve identifier, do not mistake for UUID | Tested | AppIdentifierTests |
| BVA-053 | App matching | ByHost identifier ending in deadbeef | Preserve identifier, do not mistake for UUID | Tested | AppIdentifierTests |
| BVA-054 | App matching | ByHost identifier ending in 123 | Preserve identifier, do not mistake for UUID | Tested | AppIdentifierTests |
| BVA-055 | App matching | ByHost identifier ending in empty component | Preserve identifier, do not mistake for UUID | Tested | AppIdentifierTests |
| BVA-056 | App matching | ByHost identifier ending in - | Preserve identifier, do not mistake for UUID | Tested | AppIdentifierTests |
| BVA-057 | App matching | ByHost identifier ending in App | Preserve identifier, do not mistake for UUID | Tested | AppIdentifierTests |
| BVA-058 | App matching | Valid host UUID in ByHost | Strip UUID | Tested | AppIdentifierTests |
| BVA-059 | App matching | .plist | Strip recognized suffix only | Tested | AppIdentifierTests |
| BVA-060 | App matching | .savedState | Strip recognized suffix only | Tested | AppIdentifierTests |
| BVA-061 | App matching | .binarycookies | Strip recognized suffix only | Tested | AppIdentifierTests |
| BVA-062 | App matching | no suffix | Strip recognized suffix only | Tested | AppIdentifierTests |
| BVA-063 | App matching | UUID outside ByHost | Preserve UUID component | Tested | AppIdentifierTests |
| BVA-064 | Scan lifecycle | Old scan finishes after replacement starts | New scan remains scanning | Tested | ScanStateTests |
| BVA-065 | Scan lifecycle | Replacement finishes | Results state | Tested | ScanStateTests |
| BVA-066 | Scan lifecycle | Start Over while scan waits | Late result cannot restore results | Tested | ScanStateTests |
| BVA-067 | Threat ownership | Owner path plus empty suffix | Attach | Tested | ProtectionTests |
| BVA-068 | Threat ownership | Owner path plus /Contents/MacOS/bad | Attach | Tested | ProtectionTests |
| BVA-069 | Threat ownership | Owner path plus 2 | Do not attach unrelated launch item | Tested | ProtectionTests |
| BVA-070 | Threat ownership | Owner path plus Backup/Contents/MacOS/good | Do not attach unrelated launch item | Tested | ProtectionTests |
| BVA-071 | Threat ownership | Owner path plus .other | Do not attach unrelated launch item | Tested | ProtectionTests |
| BVA-072 | Threat ownership | Owner path plus -safe | Do not attach unrelated launch item | Tested | ProtectionTests |
| BVA-073 | YARA integration | Zero source files | No compiled rules | Tested | YaraTests |
| BVA-074 | YARA integration | Malformed source | No compiled rules | Tested | YaraTests |
| BVA-075 | YARA integration | Unsupported imported module | No compiled rules | Tested | YaraTests |
| BVA-076 | YARA integration | Same rule name in two source files | Two independent rule sets | Tested | YaraTests |
| BVA-077 | YARA integration | Missing scan file | completed false | Tested | YaraTests |
| BVA-078 | YARA integration | Empty scan file | No match | Tested | YaraTests |
| BVA-079 | YARA integration | Exact test marker | probe match and completed true | Tested | YaraTests |
| BVA-080 | YARA integration | Zero timeout | completed false | Tested | YaraTests |
| BVA-081 | YARA integration | Negative timeout | completed false | Tested | YaraTests |
| BVA-082 | YARA integration | No catalog version | Incomplete status | Tested | YaraTests |
| BVA-083 | YARA integration | Catalog version and no issues | Complete status | Tested | YaraTests |
| BVA-084 | YARA integration | Catalog version with issues | Incomplete status | Tested | YaraTests |
| BVA-085 | CPU | Missing previous sample | CPU unavailable | Tested | SamplerTests.testTickBoundaries |
| BVA-086 | CPU | Total ticks zero | CPU unavailable | Tested | SamplerTests.testTickBoundaries |
| BVA-087 | CPU | Total ticks decreases by one | CPU unavailable | Tested | SamplerTests.testTickBoundaries |
| BVA-088 | CPU | Total ticks unchanged | CPU unavailable | Tested | SamplerTests.testTickBoundaries |
| BVA-089 | CPU | Busy ticks decreases while total increases | CPU unavailable, no underflow | Tested | SamplerTests.testTickBoundaries |
| BVA-090 | CPU | Busy delta zero | CPU 0 | Tested | SamplerTests.testTickBoundaries |
| BVA-091 | CPU | Busy delta half total delta | CPU 0.5 | Tested | SamplerTests.testTickBoundaries |
| BVA-092 | CPU | Busy delta equals total delta | CPU 1 | Tested | SamplerTests.testTickBoundaries |
| BVA-093 | CPU | Busy delta exceeds total delta | CPU clamped to 1 | Tested | SamplerTests.testTickBoundaries |
| BVA-094 | Processes | No processes | Empty usage | Tested | SamplerTests.testProcessBoundaries |
| BVA-095 | Processes | Two processes inside same app | One group, count two, summed memory | Tested | SamplerTests.testProcessBoundaries |
| BVA-096 | Processes | First process sample | CPU nil | Tested | SamplerTests.testProcessBoundaries |
| BVA-097 | Processes | Plain executable path | No app owner | Tested | SamplerTests.testProcessBoundaries |
| BVA-098 | Processes | Nested helper app | Outermost app owner | Tested | SamplerTests.testProcessBoundaries |
| BVA-099 | Catalog | Missing YARA source files | Empty sources | Tested | CatalogTests |
| BVA-100 | Catalog | Missing extension metadata | Empty list | Tested | CatalogTests |
| BVA-101 | Catalog | Missing Gatekeeper database | Empty hash set | Tested | CatalogTests |
| BVA-102 | Catalog | Malformed SQLite bytes | Empty team set | Tested | CatalogTests |
| BVA-103 | Catalog | Only teams table exists | Teams still loaded | Tested | CatalogTests |
| BVA-104 | Catalog | NULL team row | Ignored | Tested | CatalogTests |
| BVA-105 | Catalog | Missing hashes table | Empty hash set | Tested | CatalogTests |
| BVA-106 | Subprocess | 262144 stderr bytes before stdout | No deadlock; all stderr retained | Tested | SubprocessTests |
| BVA-107 | Subprocess | stdout after full stderr pipe | done retained | Tested | SubprocessTests |
| BVA-108 | Subprocess | Executable absent | Status -1 | Tested | SubprocessTests |
| BVA-109 | Subprocess | Exit status 7 | Status preserved | Tested | SubprocessTests |
| BVA-110 | Subprocess | Nonzero exit stderr | Error text preserved | Tested | SubprocessTests |
| BVA-111 | Subprocess | No stdout | Empty output | Tested | SubprocessTests |
| BVA-112 | Junk | download extension | Listed for Trash; unselected | Tested | JunkTests |
| BVA-113 | Junk | crdownload extension | Listed for Trash; unselected | Tested | JunkTests |
| BVA-114 | Junk | part extension | Listed for Trash; unselected | Tested | JunkTests |
| BVA-115 | Junk | partial extension | Listed for Trash; unselected | Tested | JunkTests |
| BVA-116 | Junk | opdownload extension | Listed for Trash; unselected | Tested | JunkTests |
| BVA-117 | Junk | PART extension | Listed for Trash; unselected | Tested | JunkTests |
| BVA-118 | Junk | txt extension | Not a partial download | Tested | JunkTests |
| BVA-119 | Duplicates | Two identical files of 1048575 bytes | Ignored | Tested | ClutterTests |
| BVA-120 | Duplicates | Two identical files of 1048576 bytes | One extra with original recorded | Tested | ClutterTests |
| BVA-121 | Duplicates | Two identical files of 1048577 bytes | One extra with original recorded | Tested | ClutterTests |
| BVA-122 | Large files | 104857599 bytes | Excluded | Tested | ClutterTests |
| BVA-123 | Large files | 104857600 bytes | Included, unselected | Tested | ClutterTests |
| BVA-124 | Large files | 104857601 bytes | Included, unselected | Tested | ClutterTests |
| BVA-125 | Duplicates | Equal modification dates | Lexical path breaks keeper tie | Tested | ClutterTests |
| BVA-126 | Duplicates | Downloads through /var alias | Canonical path still preselects extras | Tested | ClutterTests |
| BVA-127 | Duplicates | Duplicate changed after scan | Copy preserved | Tested | ClutterTests |
| BVA-128 | Duplicates | Original removed after scan | Copy preserved | Tested | ClutterTests |
| BVA-129 | Duplicates | Original and copy match at removal | Copy removed; original retained | Tested | ClutterTests |
| BVA-130 | Artwork | Negative icon count | Empty list without crash | Tested | ArtworkTests |
| BVA-131 | Artwork | Zero icon count | Empty list without crash | Tested | ArtworkTests |
| BVA-132 | Artwork | Empty fillers with positive count | Empty list without crash | Tested | ArtworkTests |
| BVA-133 | Selection | Same item in two categories | One item, size counted once | Tested | SelectionTests |
| BVA-134 | Selection | No selected items | Zero selected size; no confirmation | Tested | SelectionTests |
| BVA-135 | Selection | Select one item with extra | Size includes extra | Tested | SelectionTests |
| BVA-136 | Selection | Exclude only extra | Size excludes extra | Tested | SelectionTests |
| BVA-137 | Selection | Restore extra | Size restored | Tested | SelectionTests |
| BVA-138 | Selection | Deselect category | Off and empty selection | Tested | SelectionTests |
| BVA-139 | Selection | Unknown category filter | Empty result | Tested | SelectionTests |
| BVA-140 | Selection | Review while working | Remains working | Tested | SelectionTests |
| BVA-141 | Selection | Start Over while working | Remains working | Tested | SelectionTests |
| BVA-142 | Selection | Removal during scan | Failure and scanning state retained | Tested | SelectionTests |
| BVA-143 | Clutter | Modification age exactly 90 days | Strict < cutoff excludes equality | Static | ClutterScanner.scan |
| BVA-144 | Clutter | Modification age newer than cutoff | Excluded from old downloads | Static | ClutterScanner.scan |
| BVA-145 | Clutter | Modification old but added date recent | max(modified, added) retains recent download | Static | ClutterScanner.scan |
| BVA-146 | Clutter | iCloud placeholder | Skipped before hashing | Static | ClutterScanner.collect |
| BVA-147 | Clutter | Hidden files and package contents | Skipped by enumeration options | Static | ClutterScanner.collect |
| BVA-148 | Clutter | Different full hashes with same prefix | Different groups | Static | ClutterScanner.findDuplicates |
| BVA-149 | Junk | Apple caches, own cache, CloudKit | Excluded by cache filter | Static | JunkScanner.scan |
| BVA-150 | Junk | Empty allocated size | Not listed | Static | JunkScanner.sized |
| BVA-151 | Junk | Hidden Trash entries | Included except .DS_Store | Static | JunkScanner.scan / FileUtils.children |
| BVA-152 | Apps | Two installed apps claim same support path | Shared entry kept | Static | AppScanner.scan claimCount |
| BVA-153 | Apps | Shared embedded identifier | Dropped as matching evidence | Static | AppScanner.scan sharedIdentifiers |
| BVA-154 | Apps | Shared app group | Dropped as matching evidence | Static | AppScanner.scan sharedGroups |
| BVA-155 | Apps | Apple app group | Excluded | Static | AppScanner.applicationGroups |
| BVA-156 | Apps | Display name shorter than four characters | Not used for exact-name support matching | Static | AppScanner.belongs |
| BVA-157 | Apps | Missing last-used and added dates | Not marked unused | Static | AppScanner.scan |
| BVA-158 | Apps | Last-used exactly 90 days | Strict cutoff excludes equality | Static | AppScanner.scan |
| BVA-159 | Apps | Safari or current app | Not offered for uninstall | Static | AppScanner.scan |
| BVA-160 | Apps | Missing vendor uninstaller | No uninstaller action | Static | AppScanner.vendorUninstaller |
| BVA-161 | Apps | UUID-named container | Metadata owner used for matching | Static | AppScanner.libraryEntry |
| BVA-162 | Protection | File size zero | Excluded | Static | ProtectionScanner.kind |
| BVA-163 | Protection | File size 150 MiB exactly | Eligible if valid header | Static | ProtectionScanner.kind |
| BVA-164 | Protection | File size 150 MiB plus one | Excluded, including launch programs | Static | ProtectionScanner.kind / scan |
| BVA-165 | Protection | Header shorter than four bytes | Excluded | Static | ProtectionScanner.kind |
| BVA-166 | Protection | Unsupported binary magic | Excluded | Static | ProtectionScanner.kind |
| BVA-167 | Protection | Depth exceeds configured root depth | Skip descendants | Static | ProtectionScanner.loose |
| BVA-168 | Protection | 50001st entry in root | Traversal stops | Static | ProtectionScanner.loose |
| BVA-169 | Protection | Cancellation during dispatch work | Explicit token checked before next target | Static | ProtectionScanner.scan |
| BVA-170 | Protection | One YARA source fails compilation | Summary marked incomplete | Static | ProtectionScanner.scan |
| BVA-171 | Protection | YARA scan timeout or unreadable file | Not counted as completed; summary has issue | Static | YaraRules.scan / ProtectionScanner.scan |
| BVA-172 | Startup | Malformed plist | Issue recorded, not fatal | Static | StartupInspector.startupItems |
| BVA-173 | Startup | Empty ProgramArguments | No unsafe array indexing | Static | StartupInspector.item |
| BVA-174 | Startup | KeepAlive false or empty dictionary | No keep-alive trigger | Static | StartupInspector.item |
| BVA-175 | Startup | StartInterval zero or negative | No interval trigger | Static | StartupInspector.item |
| BVA-176 | Startup | Interval divisible by 3600 or 60 | Hours/minutes formatting | Static | StartupInspector.item |
| BVA-177 | Snapshots | Non-Time-Machine snapshot | Deletion refused | Static | StartupInspector.delete |
| BVA-178 | Snapshots | Malformed calendar timestamp | Round-trip date validation rejects | Static | StartupInspector.parse |
| BVA-179 | Removal | Primary Finder operation fails or is cancelled | Extras preserved | Static | FileOps.remove |
| BVA-180 | Removal | Extra removal fails | Failure reported; its bytes not credited | Static | FileOps.remove |
| BVA-181 | Removal | launchctl executable fails to launch | No wait on unlaunched Process | Static | FileOps.launchctl |
| BVA-182 | Permissions | Replacement app launch fails | Current instance stays open | Static | Permissions.relaunch |
| BVA-183 | UI | Empty review category | Fallback/empty-state rendered | Static | ReviewView |
| BVA-184 | UI | Zero-byte logarithmic card fill | Zero without log of nonpositive value | Static | CategoryCard.fill |
| BVA-185 | UI | Zero-width icon wall | Cell size stays positive | Static | IconWall.body |
| BVA-186 | UI | Zero columns or negative rows | Clamp to valid loop bounds | Static | IconWall.body |
| BVA-187 | UI | Missing SVG asset | Optional image path does not force unwrap | Static | SVGImage.named |
| BVA-188 | Debug | Snapshot step only colons | Skip empty parts | Static | DebugSnapshot.runIfRequested |
| BVA-189 | Debug | NaN/infinite/negative/zero dimensions | Rejected | Static | DebugSnapshot.runIfRequested |
| BVA-190 | Debug | Dimensions exceed 16384 | Rejected | Static | DebugSnapshot.runIfRequested |
| BVA-191 | Debug | NaN/infinite/negative/over-hour delay | Ignored before integer conversion | Static | ModuleModel.removeSelected |
| BVA-192 | Packaging | Build command fails | set -e prevents packaging stale build | Static | Baseline scripts/build-app.sh |
| BVA-193 | Packaging | No signing identity | Ad-hoc fallback | Static | Baseline scripts/build-app.sh |
| BVA-194 | Packaging | Paths containing spaces | Quoted shell paths and arrays | Static | Baseline build-app.sh / package.sh |
| BVA-195 | Packaging | Temporary staging directory | EXIT trap cleans it | Static | Baseline scripts/package.sh |
| BVA-196 | Resources | Missing SF/SVG artwork | Does not change removal behavior | Static | Components / CardArt |
| BVA-197 | Particles | Window resize | Emitter positions recomputed in layout | Static | Particles.swift |
| BVA-198 | Permissions | Full Disk Access denied, then granted | Verify onboarding polling and post-relaunch scan coverage | Not executed | Live system / further validation |
| BVA-199 | Finder | Administrator prompt cancelled | Verify app remains and support files are retained | Not executed | Live system / further validation |
| BVA-200 | Finder | Automation denied | Verify explanatory error reaches failure log | Not executed | Live system / further validation |
| BVA-201 | Startup | Loaded user agent removed | Verify unload and Trash integration on disposable agent | Not executed | Live system / further validation |
| BVA-202 | Snapshots | Real Time Machine snapshot deletion | Verify only the confirmed snapshot disappears | Not executed | Live system / further validation |
| BVA-203 | UI | Minimum window, resizing, VoiceOver and reduced motion | Verify visual layout and accessibility on desktop | Not executed | Live system / further validation |
| BVA-204 | Filesystem | Concurrent ancestor replacement during removal | Path validation is not an atomic descriptor-relative filesystem transaction | Not executed | Live system / further validation |
| BVA-205 | YARA | All vendored C parser/VM input space | Requires upstream corpus, sanitizers and fuzzing; wrapper tests do not establish memory safety | Not executed | Live system / further validation |
| BVA-206 | Protection | Live evolving Apple signatures and Gatekeeper schemas | Validate against supported macOS versions; unreadable or missing database tables must mark coverage incomplete | Not executed | Live system / further validation |
| BVA-207 | Packaging | New concurrent universal build and release edits | Outside this review snapshot; validate independently | Not executed | Live system / further validation |

## Implementation coverage

- `FileUtils`, `Models`: path boundaries, per-item failures, bytes, duplicates, selection, cancellation and state transitions.
- `AppScanner`, `ClutterScanner`, `JunkScanner`: identifier/date/size boundaries, matching ownership, safe defaults, unavailable metadata and scan fixtures.
- `ProtectionScanner`, `Yara`, `XProtectCatalog`: collection limits, rule compilation, match ownership, scan errors, catalog reads and cancellation. Vendored C is covered by integration execution rather than exhaustive source analysis.
- `SystemSampler`, `StartupInspector`, `PerformanceModel`: counter deltas, grouping, plist fallbacks, process output and snapshot deletion gates.
- Views, `Module`, `ViewState`, `Permissions`, `SqueakyApp`, `DebugSnapshot`: empty/working/results branches, sizing and numeric conversions, resource fallbacks, launch lifecycle and diagnostic inputs. Visual rendering and OS dialogs are not covered by XCTest assertions.
- Baseline scripts, package manifest and resources: quoting, failure propagation, build/signing flow and resource-loading assumptions. Reference images and generated build outputs are not executable application implementation.

## Practical limits

File checks and hashing reduce stale-result risks but cannot prevent a different process from replacing paths between validation and mutation. A fully race-resistant removal engine needs descriptor-relative operations and a separate design for Finder/Trash semantics. Byte totals reflect allocated bytes observed immediately before successful operations; Trash moves do not necessarily reclaim physical disk space immediately, and APFS clones/hard links can affect reclamation.

Protection remains a scoped, on-demand scan. Traversal depth, file size, package handling, access permissions, unsupported formats and Apple's changing catalogs constrain coverage. Incomplete YARA coverage is now reported, and missing or unreadable Gatekeeper tables also mark coverage incomplete. App ownership matching remains heuristic and leftovers stay unselected.

The baseline packaging scripts were read before concurrent changes appeared. Those edits, the new release script, and the new license were preserved and excluded from review commits.
