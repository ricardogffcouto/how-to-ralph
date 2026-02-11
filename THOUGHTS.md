# Evolution of the Ralph Methodology

This document tracks high-level thoughts, architectural evolutions, and iterative improvements to the Ralph autonomous coding system.

## Core Strategy & Observations

### 1. Methodology-Aware Agents
*   **The Theory**: Keeping a copy of the Ralph Playbook/methodology in the project root (e.g., `PLAYBOOK.md` or `index.html`) acts as a "meta-prompt."
*   **The Benefit**: When the agent understands the *process* it is currently inhabiting (reading specs -> planning -> building -> backpressure), it is significantly better at scaffolding projects and writing specs that are compatible with the loop's constraints.

### 2. Multi-CLI Loop Generalization
*   **Goal**: Generalize `loop.sh` or create targeted versions for `codex`, `gemini-cli`, `opencode`, and `amp`.
*   **Optimization**: Use `jq` to parse structured JSON output from these CLIs. This allows the bash loop to better manage rate limits, context window exhaustion, and token usage by reacting to the metadata provided by the models.

### 3. Greenfield Scaffolding
*   **Scaffold Plan**: Initial planning should explicitly target a methodology-friendly stack (e.g., Rust + TS) to ensure type safety and performance from day one.
*   **Design Tokens**: Include a plan for a simple, shared design system early. 
    *   *Reference pattern*: "I want this to look like the Flo period tracker, but for tennis."
    *   *Mocking*: Use **MSW (Mock Service Worker)** for rapid UI prototyping and API mocking before the backend is fully solidified.

### 4. High-Level Backpressure (Stability over Fragility)
*   **The Problem**: Unit tests often break during heavy refactors, causing Ralph to get stuck in "fix-the-test" loops.
*   **The Solution**: Shift toward **Playwright-CLI** for E2E tests as the primary backpressure mechanism.
*   **Principle**: Find the highest level of testing appropriate for the feature. If the user journey is intact (SLC - Simple, Lovable, Complete), the internal implementation details matter less during rapid iteration.

### 5. Visual Feedback & UI/UX Loop
*   **Agentation**: Integrate tools like [Agentation](https://github.com/agentation/agentation) to provide a visual feedback toolbar. This allows the human "outside the loop" to visually inspect UI/Frontend progress and provide targeted corrections without diving into code.

### 6. Automated Observability (CLI-Native Debugging)
*   **Concept**: Automate the flow of logs and system state back to the LLM.
*   **Implementation Ideas**:
    *   Create a structured logs folder (e.g., `.ralph/logs/`) that the agent is instructed to check during "Investigate" phases.
    *   Implement a CLI-based "debug page" (similar to Django's debug view) that dumps application state, active routes, and database schemas into a format easily digestible by subagents.

---

## Iterative Evolution Plan

- [ ] **Task 1**: Generalize `loop.sh` to support `gemini-cli` and `codex` using `jq`.
- [ ] **Task 2**: Create a `SCAFFOLD_TEMPLATE.md` that incorporates the Rust/TS and MSW patterns.
- [ ] **Task 3**: Integrate Playwright as the default test runner in `AGENTS.md` for a sample project.
- [ ] **Task 4**: Research/implement a "Log-to-LLM" utility that aggregates errors into a single file for the agent.
