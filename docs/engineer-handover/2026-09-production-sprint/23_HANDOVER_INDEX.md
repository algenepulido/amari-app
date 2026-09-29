# Handover index

All files in `docs/engineer-handover/2026-09-production-sprint/`. The findings register, the
authorisation matrix and the device matrix are living documents: Algene updates them as the sprint
proceeds and they become the sprint's evidence.

| File | Purpose | Who uses it | Read before coding? | Updated during sprint? |
|---|---|---|---|---|
| `00_READ_ME_FIRST.md` | Entry point, generation record, request status A to I | Algene, Jeremy | Yes | At the end |
| `01_EXECUTIVE_TECHNICAL_HANDOVER.md` | Product, architecture, risks, what not to redesign, success | Algene | Yes | No |
| `02_SYSTEM_ARCHITECTURE.md` | Layers, dependencies, six diagrams, current against proposed | Algene | Skim | If architecture changes |
| `03_REPOSITORY_AND_LOCAL_SETUP.md` | Layout, commands, env names, profiles, routing | Algene | Yes, hour one | If commands change |
| `04_ACCESS_AND_ENVIRONMENT_REQUIREMENTS.md` | Environment options and access matrix | Jeremy, Algene | Yes | As access is granted |
| `05_FEATURE_BY_FEATURE_TECHNICAL_REVIEW.md` | Feature review with status and priority | Algene | Reference | Yes, statuses |
| `06_PRODUCTION_READINESS_BASELINE.md` | Reconciliation of earlier reports and current baseline | Algene, Jeremy | Yes, P0 and P1 | Summarise changes at the end |
| `07_AUTHORIZATION_MATRIX_STARTER.csv` | 151 resource and operation rows, expected by actor, RESULT UNTESTED | Algene | Yes | **Living** |
| `08_DATABASE_SECURITY_INVENTORY.md` | Counts, tables, triggers, storage, cron, 65 SECURITY DEFINER functions | Algene | Reference | If schema changes |
| `09_AUTH_SESSION_AND_DEEPLINK_MAP.md` | Auth stages, source against device tests | Algene | Yes | With findings |
| `10_IOS_ANDROID_RELEASE_STATE.md` | Release engineering and external store checks | Algene, Jeremy | Before any build | Yes |
| `11_DEVICE_TEST_MATRIX.csv` | 116 journey and condition rows, RESULT NOT RUN | Algene | Before device work | **Living** |
| `12_TEST_IDENTITY_AND_INVITE_REQUIREMENTS.md` | Identities, tooling, secure handoff table | Jeremy | Jeremy, yes | Handoff table |
| `13_MEDIA_V1_CURRENT_STATE_AND_GAP_PLAN.md` | Media state, decisions, V1 shape | Algene, Jeremy | Before Media work | Yes |
| `14_OBSERVABILITY_AND_OPERATIONS.md` | Operational surface and acceptance criteria | Algene | Before Sentry work | Yes, record findings |
| `15_PERFORMANCE_SCALE_AND_COST_TEST_PLAN.md` | Hot paths, test plan, cost template | Algene | Before scale work | Yes, results and costs |
| `16_FINDINGS_REGISTER.csv` | Master register, 49 rows | Algene, Jeremy | Yes | **Living** |
| `17_RELEASE_AND_ROLLBACK_RUNBOOK.md` | Release paths and rollback reality | Algene, Jeremy | Before any release | If the path changes |
| `18_EXTERNAL_ENGINEER_ACCESS_CHECKLIST.md` | Owner checklist | Jeremy | Jeremy, yes | Yes |
| `19_FIRST_FOUR_HOURS.md` | First session plan | Algene | Yes | No |
| `20_SPRINT_SEQUENCE.md` | Dependency order and milestones | Algene, Jeremy | Yes | If plan changes |
| `21_OPEN_QUESTIONS_FOR_JEREMY.md` | Owner decisions and access questions | Jeremy | Jeremy, yes | Answers recorded |
| `22_SOURCE_EVIDENCE_LEDGER.md` | Claim to evidence mapping | Reviewers | Reference | Add rows for new claims |
| `23_HANDOVER_INDEX.md` | This index | Everyone | No | If files are added |
