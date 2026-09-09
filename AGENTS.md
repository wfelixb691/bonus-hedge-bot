# Project Engineering Rules

Whenever the user mentions **"loop engineering"**, **"hermes loop"**, or the shortcut **`#loop`**:
- Immediately invoke and follow the `loop-engineering` skill.
- Apply first-principles root-cause analysis on the entire architecture.
- Stress-test against all 5 distributed system failure modes (concurrency, buffer flushing, clock drift, snapshot persistence, and genuine liquidation).
- Avoid quick superficial patches; verify solutions rigorously before proposing.
