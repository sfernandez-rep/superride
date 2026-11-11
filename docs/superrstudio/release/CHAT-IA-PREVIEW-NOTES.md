# Chat IA: notes for the next SuperR preview

Text for the next preview's release notes, ready to merge into
[RELEASE-NOTES.md](RELEASE-NOTES.md). Chat IA is **experimental**. It is
available only in SuperR Desktop with the SuperR experimental features enabled.

## New: Chat IA, an R assistant inside SuperR

- **Gemini built in.** A *Chat IA* button in the toolbar opens a side panel.
  It chats with Google Gemini through the Gemini API and streams the answer as
  it arrives. You can stop an answer or start a new conversation at any time.
- **Your own free key.** You create an API key in Google AI Studio with your
  Google account, in a project without billing, and paste it into the panel.
  - SuperR checks the key with Google first, then stores it encrypted with the
    system's credential storage (Windows DPAPI). It is never shown again,
    never written to logs or project files, and never sent anywhere but Google.
  - SuperR asks for no card and never enables billing.
  - Only text models that Google lists with a free tier are offered.
- **Help with R projects.** Below the message box you choose what Gemini may
  see:
  - **General chat**: only what you type.
  - **Current file**: the document open in the editor, including unsaved
    changes and the selected code.
  - **Project**: read-only access to the open RStudio project. Gemini asks
    for the files it needs; SuperR reads them and lists, under your message,
    exactly which files were sent.
- **Safe file access.** In project mode SuperR reads only inside the project:
  - only R scripts, R Markdown, Quarto and text data;
  - it never reads `.env`, credential-like files, `.git` or `renv`, and it
    follows no link that leads outside the project;
  - `.rds` and `.RData` files are never read;
  - large data files are read only from the start;
  - your home folder or a drive root are never treated as a project.
- **Reviewable edits.** Ask Gemini to fix or improve a script and it
  *proposes* a change. SuperR shows a diff with **Accept** and **Reject**.
  - Accepted changes are applied in the editor, unsaved; Ctrl+Z or **Revert**
    undoes them.
  - A proposal is refused if the file changed after it was made.
  - Changes to several files are applied all or nothing.
  - Chat IA never saves files, runs code or installs packages.
- **A panel that fits the IDE.**
  - It follows the light and dark themes.
  - It shows the real connection state: connected, checking, generating,
    offline, error, or quota exhausted.
  - Answers are formatted, with tables and highlighted R code, and code blocks
    have *Copy* and *Insert in editor*.
  - Enter sends; Shift+Enter adds a line.
  - Editor actions explain a selection, explain a file, review code, or send a
    selection to the chat.

## Privacy and the free quota

- On Gemini's **free tier, Google may use what you send, including any file
  contents you allow it to read, to improve its products, and human reviewers
  may read it.** Do not send personal, confidential or sensitive data.
- Free limits belong to **your** Google project and model; for example,
  5 requests per minute and 20 per day. Each time Gemini reads project files
  uses one more request. When a limit is reached, SuperR shows the limit and
  retry time that Google reported. *View my project's limits* opens Google AI
  Studio's own page.
- Google's Gemini API terms require users to be 18 or older and describe the
  API as intended for developers. In the European Economic Area, Switzerland
  and the United Kingdom, apps may offer only Google's paid service.
- Signing in with a personal Google account through Google's Antigravity tool
  is **not** offered: Google's terms do not allow third-party apps to use it on
  consumer plans.

## Current limitations

- Experimental and Desktop only. Without the experimental features the button
  does not appear. In a browser session (server) the panel can only report
  that it is unavailable, because it needs the desktop's own bridge.
- Gemini API only. The Codex and Antigravity agents are listed but stay
  disabled until their isolation is verified.
- Analysing a large project can use several requests of the daily quota.
  Projects with more than 300 readable files are only partly indexed.
- Proposals can change existing `.R`, `.Rmd` and `.qmd` files. They cannot
  create or delete files.
- Binary R data (`.rds`, `.RData`) is never read.
- Accepted changes stay unsaved. When you save, RStudio's "Line ending
  format" option applies as for any edit. Its default, "native", writes CRLF on
  Windows; choose "Passthrough" to keep a file's own line endings.
- Conversations are kept in memory only and are lost when SuperR closes.
- The editor actions are in the panel, not in the editor's context menu.
