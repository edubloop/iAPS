# SwiftLint Warning Triage — iAPS

**Baseline:** 359 warnings, 0 errors (branch: `dev-ci-hardening`)
**Date:** 2026-03-16
**Target:** ≤200 warnings after triage
**Achieved:** 172 warnings (52% reduction)

---

## Rule Breakdown (descending by count)

| # | Rule | Count | Decision | Rationale |
|---|------|-------:|----------|-----------|
| 1 | `opening_brace` | 108 | **Auto-fix** | Pure style; `swiftlint --fix` resolves safely |
| 2 | `line_length` | 49 | **Tolerate** | Threshold already relaxed to 230; remaining lines are legitimately long in medical algorithm code |
| 3 | `type_body_length` | 31 | **Tolerate** | Complex medical-domain state models; refactoring is high-risk without functional benefit |
| 4 | `implicit_optional_initialization` | 26 | **Disable** | Explicit `= nil` is idiomatic and readable; rule is controversial and conflicts with established codebase style |
| 5 | `todo` | 23 | **Tolerate** | Legitimate upstream integration TODOs; worth tracking, not suppressing |
| 6 | `function_parameter_count` | 13 | **Tolerate** | Threshold already relaxed to 6/15; medical calculation functions require many typed params |
| 7 | `closure_parameter_position` | 12 | **Auto-fix** | Style-only; safe to auto-correct |
| 8 | `cyclomatic_complexity` | 11 | **Tolerate** | Threshold already relaxed to 15/150; medical decision logic is inherently complex |
| 9 | `redundant_void_return` | 9 | **Auto-fix** | Mechanical style issue; safe |
| 10 | `prefer_type_checking` | 7 | **Fix incrementally** | `as? X != nil` → `is X` is a safe, mechanical substitution |
| 11 | `for_where` | 7 | **Tolerate** | Structural refactor in APS/medical code; risk not justified by style gain |
| 12 | `nesting` | 7 | **Tolerate** | SwiftUI DSL requires nesting; flagged types are SwiftUI view helpers |
| 13 | `leading_whitespace` | 5 | **Auto-fix** | Style-only; safe |
| 14 | `file_length` | 5 | **Tolerate** | Large files are structural (APSManager, etc.); splitting requires architectural review |
| 15 | `statement_position` | 4 | **Auto-fix** | Style-only; safe |
| 16 | `vertical_whitespace` | 4 | **Auto-fix** | Style-only; safe |
| 17 | `unused_enumerated` | 3 | **Fix incrementally** | `.indices` vs `.enumerated()` is mechanical and safe |
| 18 | `unneeded_synthesized_initializer` | 3 | **Auto-fix** | Safe removal of compiler-generated boilerplate |
| 19 | `comment_spacing` | 3 | **Auto-fix** | Style-only; safe |
| 20 | `multiple_closures_with_trailing_closure` | 3 | **Tolerate** | Style preference; SwiftUI idiom makes this unavoidable |
| 21 | `unused_optional_binding` | 3 | **Tolerate** | Needs case-by-case review; keeping as signal |
| 22 | `private_over_fileprivate` | 3 | **Tolerate** | Architectural visibility decisions; not safe to change without review |
| 23 | `legacy_random` | 3 | **Auto-fix** | Safe modernization (`arc4random` → `Int.random`) |
| 24 | `comma` | 2 | **Auto-fix** | Style-only; safe |
| 25 | `function_body_length` | 2 | **Tolerate** | Threshold already relaxed to 300/500; flagged functions are medical algorithms |
| 26 | `legacy_constructor` | 2 | **Auto-fix** | Safe modernization (`CGRect(x:y:width:height:)` form) |
| 27 | `is_disjoint` | 2 | **Fix incrementally** | `.isDisjoint(with:)` is semantically clearer; safe API swap |
| 28 | `trailing_newline` | 2 | **Auto-fix** | Style-only; safe |
| 29 | `unneeded_override` | 2 | **Fix incrementally** | Empty WatchKit overrides; safe to remove |
| 30 | `compiler_protocol_init` | 1 | **Auto-fix** | Safe modernization |
| 31 | `computed_accessors_order` | 1 | **Tolerate** | Low signal; isolated case |
| 32 | `void_function_in_ternary` | 1 | **Tolerate** | Low signal; isolated case |
| 33 | `static_over_final_class` | 1 | **Tolerate** | Architectural decision; needs review |
| 34 | `function_name_whitespace` | 1 | **Tolerate** | Low signal; isolated case |

---

## Decision Summary

| Decision | Rules | Warnings Removed |
|----------|-------|----------------:|
| **Auto-fix** | opening_brace, closure_parameter_position, redundant_void_return, leading_whitespace, statement_position, vertical_whitespace, unneeded_synthesized_initializer, comment_spacing, legacy_random, comma, legacy_constructor, trailing_newline, compiler_protocol_init | **158** |
| **Disable** | implicit_optional_initialization | **26** |
| **Fix incrementally** | prefer_type_checking, unused_enumerated, is_disjoint, unneeded_override | **~14** |
| **Tolerate** | line_length, type_body_length, todo, function_parameter_count, cyclomatic_complexity, for_where, nesting, file_length, multiple_closures_with_trailing_closure, unused_optional_binding, private_over_fileprivate, function_body_length, computed_accessors_order, void_function_in_ternary, static_over_final_class, function_name_whitespace | **~161** |

**Final count: 172 warnings** (target was <200 ✓, 52% reduction from 359)

---

## Constraints Observed

- No changes to `FreeAPS/Sources/APS/` without explicit safety review — auto-fix applies mechanical formatting only
- All rule disables are justified inline in `.swiftlint.yml`
- Each commit group is independently revertable
- Build must pass after each commit

---

## Preventing Backsliding

The CI lint workflow (`.github/workflows/lint.yml`) should:
1. Run `swiftlint lint --reporter json` and count warnings
2. Compare against the baseline stored in `SWIFTLINT_TRIAGE.md` or a `.swiftlint-baseline` file
3. **Fail if warning count increases** (new violations block merge)
4. **Succeed if warning count stays equal or decreases** (improvements are always welcome)

This asymmetric policy ("block increases, tolerate existing") prevents backsliding without blocking progress.

---

## Open Items

- [ ] `for_where` (7): Revisit when APS core logic has dedicated test coverage
- [ ] `nesting` (7): Evaluate SwiftUI view decomposition in a separate refactor PR
- [ ] `private_over_fileprivate` (3): Architectural visibility audit
- [ ] `todo` (23): Review upstream [loopkit] TODOs for resolution or permanent documentation
