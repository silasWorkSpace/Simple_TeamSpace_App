# AI Operating Constitution (GEMINI.md)

## Permanent Governance & Workflows

### 1. Approval Workflow
- **Proposals**: All design decisions (architecture, protocol, database) must be proposed in `implementation_plan.md` under "Future Proposals".
- **Confirmation**: AI must wait for explicit user approval before modifying any source files.
- **Scope Locking**: Once a milestone is approved, its scope is locked. Changes require a new approval cycle.

### 2. Implementation Workflow
- **Design Review**: AI must explain the technical design and file impacts before writing code.
- **Surgical Edits**: Prefer `replace` tool to minimize context bloat and ensure precise changes.
- **Small Batches**: Implement one logical component at a time (e.g., Server Service -> Server Handler -> Client Service).

### 3. Verification Workflow
- **Mandatory Validation**: Every milestone must conclude with a standalone verification script or test suite.
- **Evidence**: Provide logs, database snapshots, or runtime results as evidence of success.
- **Audit Requirement**: Before final approval, provide a full audit of modified files and implemented facts.

### 4. Documentation Workflow
- **Baseline Integrity**: Documentation must always reflect the *actual* implemented state of the project.
- **Fact vs. Proposal**: Clearly segregate "Implemented Facts" from "Future Proposals".
- **Continuous Update**: Update relevant `.md` files immediately after a feature is verified.

### 5. Technical Discipline
- **Milestone Discipline**: Do not leak implementation details or code from future milestones into the current one.
- **Architecture Locking**: No new architectural patterns (e.g., DI frameworks, Repository pattern) without explicit approval.
- **Protocol Rigor**: Adhere strictly to the framing and structure defined in `protocol.md`.
- **Database Rules**: Follow the "Open-Execute-Close" pattern and parameterized query mandate defined in `development_standards.md`.

### 6. Audit Gate Rule (Mandatory)
Before any implementation phase begins:
- **Findings Resolution**: All audit findings must be resolved.
- **Blockers**: Any unresolved architectural gap, ambiguity, missing dependency, or protocol inconsistency blocks implementation.
- **Approval Logic**: The presence of a Design Proposal or Implementation Plan alone is NOT approval to code.
- **Final Gate**: Implementation may begin only after:
  - Design Proposal approved.
  - Audit findings resolved.
  - Implementation Plan approved.
  - Explicit implementation approval received.
- **Workflow**: Design -> Audit -> Clarification -> Re-Audit -> Implementation Plan -> Audit -> Explicit Approval -> Implementation.
- **Forbidden**: Starting implementation while audit questions remain unanswered; assuming missing capabilities; expanding scope to compensate; creating UI flows for missing backend features.

### 7. Scope Lock Rule
During implementation:
- **Strict Adherence**: Only files explicitly listed in the approved scope may be modified.
- **Deviation Protocol**: If implementation requires touching an additional file:
  1. Stop.
  2. Explain why.
  3. Produce a scope expansion proposal.
  4. Wait for approval.
- **Implicit Modifications**: Never modify extra files implicitly.
- **Placeholders**: Never create placeholder features for missing backend functionality without approval.
- **Assumptions**: Never convert a planning assumption into implemented behavior.

## Current State
- **Active Milestone**: None (Transitioning to Milestone 3).
- **Locked Items**: Core TCP Framing, Bcrypt Auth, Users Schema, Session Mapping.
