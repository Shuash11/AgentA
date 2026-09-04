# AgentA Traceability Matrix Revision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a separate, formally written DOCX that preserves the original AgentA traceability matrix while making it understandable to a lecturer or assessor without requiring source-code knowledge.

**Architecture:** Use `python-docx` to open the source document, replace only its text content, and save a new file beside it. Preserve the existing paragraph order, table dimensions, and formatting containers; validate both structure and language after generation.

**Tech Stack:** Python 3, `python-docx`, Microsoft Word Open XML (`.docx`)

---

### Task 1: Create the document revision utility

**Files:**
- Create: `tools/revise_agenta_traceability_matrix.py`
- Read: `C:\Users\joashua\Downloads\AgentA_FR_Design_Pattern_Traceability_Matrix (1).docx`
- Create: `C:\Users\joashua\Downloads\AgentA_FR_Design_Pattern_Traceability_Matrix_REVISED.docx`

- [ ] **Step 1: Define source and output paths**

Use `pathlib.Path` constants for the exact source and output paths above. Refuse to overwrite the source and fail clearly if the source is missing.

- [ ] **Step 2: Define the approved paragraph replacements**

Use these exact replacements:

```text
AgentA: An AI-Based Learning Assistant
Functional Requirement-Design Pattern Traceability Matrix

This matrix links AgentA's main functional requirements to the software design patterns used in the system. For each requirement, it states what the pattern does, where it is used, and why it suits the required behavior. Technical names appear only when they are needed to show traceability.

Summary

AgentA uses the Facade pattern for account, profile, recovery, and security functions. This lets each screen call a service instead of managing every step itself. The Observer pattern updates the chat interface and theme when their state changes, while the Strategy pattern selects an online or offline response method based on connection status. The Repository, Chain of Responsibility, Command, and State patterns support chat-session management, password recovery, account deletion, and navigation.
```

- [ ] **Step 3: Define the approved table replacements**

Keep the existing header row and use the following content for rows 1-10:

| Functional Requirement | Design Pattern | Purpose of the Pattern | Application in the System | Justification |
|---|---|---|---|---|
| User Registration & Recovery Code Generation | Facade Pattern | Presents registration through one service that coordinates input checks, account creation, and recovery code generation. | The registration screen uses AuthService to manage account validation and creation instead of handling each step itself. | Registration has several related steps. Placing them in AuthService avoids repeating the same work in the screen and gives users a consistent registration process. |
| User Login & Session Handling | Facade Pattern + Singleton Pattern | The Facade pattern gives the screen one point of access to authentication. The Singleton pattern keeps one shared authentication state while the application is running. | AuthService checks the login details and establishes the current user session before the Dashboard opens. | A user should receive one clear login result. Centralized authentication and one shared session state reduce the risk of conflicting account information. |
| Password Recovery via Recovery Code | Chain of Responsibility Pattern | Arranges password recovery as a sequence in which one stage must be completed before the next can begin. | RecoveryCodeService checks the recovery code first. A user can set a new password only after the code is accepted. | The sequence prevents a password change before identity verification. If verification fails, the process stops and the user receives an error. |
| Chat Session Management (Dashboard) | Repository Pattern | Centralizes the creation, retrieval, and deletion of chat-session records. | The Dashboard manages the user's chat sessions and provides access to previous conversations. | A central collection keeps conversation history organized and removes data-management work from the interface. |
| Conversational Chat Interface (Message Display) | Observer Pattern | Updates parts of the interface automatically when the conversation state changes. | The message list, typing indicator, and conversation position change as messages are sent and received. | The interface must show each exchange as it happens. State-based updates keep the conversation current without a manual refresh. |
| Dual-Mode Response Engine (Online/Offline Routing) | Strategy Pattern | Defines alternative response methods and selects one without changing how the user sends a message. | The response engine uses the online AI service when an internet connection is available. When the device is offline, it uses a local keyword-based response. | Both modes answer the user's message, but they rely on different resources. Choosing the method at runtime allows the chat to remain available when the connection changes. |
| Profile Viewing and Editing | Facade Pattern | Places profile validation, saving, and confirmation behind one service. | ProfileService manages changes submitted through the Edit Profile screen and confirms when they have been saved. | The screen can focus on user input while ProfileService handles the rules for checking and saving profile information. |
| Security Settings (View Recovery Code / Delete Account) | Facade Pattern + Command Pattern | The Facade pattern gives the screen controlled access to security functions. The Command pattern treats account deletion as a separate action that must be confirmed before it runs. | SecurityService allows users to view the recovery code or delete an account. Deletion starts only after the required confirmation steps are completed. | Security functions need one controlled access point. Treating deletion as a separate, confirmable action reduces the chance of accidental data loss. |
| Theme Management (Dark/Light Mode Toggle) | Observer Pattern | Notifies relevant screens when a shared display preference changes. | ThemeNotifier stores the light or dark theme choice and applies it across the application. | The theme affects several screens. A shared notification mechanism applies the same choice everywhere as soon as the user changes it. |
| Bottom Navigation Bar (Tab Switching) | State Pattern | Changes navigation behavior according to the tab that is currently selected. | The bottom navigation bar tracks the active tab, opens a newly selected section, and does nothing when the current tab is selected again. | The result of a tap depends on the active tab. Tracking that state prevents unnecessary navigation and makes the behavior predictable. |

- [ ] **Step 4: Preserve formatting while replacing text**

Open the source with `Document`, replace the five non-empty paragraph texts by index, replace all 55 table-cell values, and save to the output path. When replacing text, retain the first run's formatting where possible instead of replacing paragraph objects or table structures.

- [ ] **Step 5: Run the utility**

Run:

```powershell
python tools/revise_agenta_traceability_matrix.py
```

Expected: exit code 0 and confirmation of the revised output path.

### Task 2: Validate the revised document

**Files:**
- Create: `tests/test_agenta_traceability_matrix_revision.py`
- Test: `C:\Users\joashua\Downloads\AgentA_FR_Design_Pattern_Traceability_Matrix_REVISED.docx`

- [ ] **Step 1: Add structural assertions**

Assert that the output exists, can be opened by `python-docx`, contains one table, contains 11 rows and 5 columns, retains the two headings, and contains all ten original functional-requirement names.

- [ ] **Step 2: Add readability and cleanup assertions**

Assert that the combined text does not contain `.dart`, `()`, `ChangeNotifierProvider`, `PageRouteBuilder`, `_generateReply`, `1.2 seconds`, `1-second delay`, or the Unicode replacement character `\ufffd`. Assert that `AuthService`, `RecoveryCodeService`, `ProfileService`, `SecurityService`, and `ThemeNotifier` remain for essential traceability.

- [ ] **Step 3: Run the validation**

Run:

```powershell
python -m unittest tests.test_agenta_traceability_matrix_revision -v
```

Expected: all tests pass.

### Task 3: Perform final document review

**Files:**
- Review: `C:\Users\joashua\Downloads\AgentA_FR_Design_Pattern_Traceability_Matrix_REVISED.docx`

- [ ] **Step 1: Extract the final text for review**

Print all non-empty paragraphs and every table row with `python-docx`. Confirm that the generated wording exactly matches Task 1.

- [ ] **Step 2: Inspect document package integrity**

Open the output as a ZIP package and run `ZipFile.testzip()`. Expected: `None`, meaning no corrupt package member is found.

- [ ] **Step 3: Confirm source preservation**

Verify the original and revised files both exist and have different file paths. Do not modify or remove the source file.

- [ ] **Step 4: Report the output**

Provide the revised DOCX path and summarize the successful structural, language, and package-integrity checks. Git commit steps are intentionally omitted because `C:\projects\aiproject` is not a Git repository.
