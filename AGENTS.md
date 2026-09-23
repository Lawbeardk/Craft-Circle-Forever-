# CraftCircle WF contributor guidance
- Target WoW Forever and its modern API surface.
- Preserve existing SavedVariables when changing schemas.
- Never send unbounded addon messages; validate sizes and hashes.
- Prefer item and recipe IDs over localized names in protocols.
- Keep guild sync backward-compatible or bump `PROTOCOL`.
- Do not print routine scans or sync traffic to chat.
- Test with an unguilded alt because account-wide profession visibility is required.
- Update README and TOC version for releases.
