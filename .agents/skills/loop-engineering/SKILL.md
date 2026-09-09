---
name: loop-engineering
description: >-
  Strict Closed-Loop Engineering and Exhaustive Root-Cause Verification Protocol.
  Activate when the user asks for 'loop engineering', 'hermes loop', 'deep verification',
  'mode loop', or when solving mission-critical distributed systems, concurrency race conditions,
  trading bots, or complex debugging tasks where surface-level trial-and-error must be avoided.
---

# Closed-Loop Engineering Protocol (Hermes / DeepSeek Standard)

This skill enforces a rigorous, multi-stage engineering cycle designed to prevent superficial patching, trial-and-error loops, and unverified assumptions.

## Core Philosophy
1. **Never patch symptoms**: Identify and fix the structural first-principles flaw.
2. **Never guess**: Inspect real logs, memory layouts, protocol headers, and actual file state.
3. **Exhaustive edge-case verification**: Before proposing or finalizing code, validate against the 5 Failure Modes.

---

## The 5 Failure Modes Stress-Test Matrix

Every distributed system or mission-critical logic (e.g. Dual-MT5 EA, Websockets, File IPC) MUST be stress-tested against:

1. **Racy Partial Read / Write**:
   - What happens if Process B reads while Process A is mid-write?
   - *Requirement*: Protocol Magic Header (`0x42484246`), versioning, and length-checked buffers.
2. **OS I/O Caching & Buffering**:
   - What happens if the OS hasn't written buffers to physical storage?
   - *Requirement*: Explicit flush (`FileFlush()`) before releasing file locks.
3. **Clock / Timezone Drift**:
   - What happens if Server A and Server B have a 30-second clock skew?
   - *Requirement*: Monotonically increasing sequential counter IDs instead of raw timestamps.
4. **Transient Lag vs Hard Failure**:
   - What happens if a network packet drops for 500ms?
   - *Requirement*: Snapshot persistence (retain last good valid state) with debounced grace periods (e.g. 30s) before declaring offline.
5. **Real Emergency Execution**:
   - What happens during true liquidation/stop-out?
   - *Requirement*: Strict state distinction between communication lag and actual margin drop (e.g. Equity < $10).

---

## Execution Workflow

1. **Hypothesis & Full Codebase Survey**: Read complete relevant code blocks before suggesting changes.
2. **First-Principles Architecture**: Design atomic, resilient protocols.
3. **Zero-Assumption Self-Critique**: Mentally execute the logic through all 5 failure modes.
4. **Holistic Delivery**: Deliver complete, production-ready, error-free implementations with 0 regressions.
