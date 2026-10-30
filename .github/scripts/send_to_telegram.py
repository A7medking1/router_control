"""Upload a build artifact to a Telegram chat using Pyrogram (kurigram) with a bot token.

Uses MTProto (not the HTTP Bot API) so we can send files larger than 50 MB.
`in_memory=True` is required for CI so no session file is persisted.

Reads from env:
    API_ID, API_HASH, BOT_TOKEN, CHAT_ID  - credentials
    ARTIFACT_PATH                          - path to file to upload (required)
    ARTIFACT_LABEL                         - caption label, e.g. "Release APK"
    ARTIFACT_FILENAME                      - optional upload filename override
    APP_NAME                               - per-repo identifier (used in caption)
    TOPIC_ID                               - forum topic thread id to send into (optional)
    API_ENV                                - testing | production (optional, tags the caption)
    BRANCH_NAME, COMMIT_SHA, COMMIT_MESSAGE - for caption
"""

import asyncio
import os
import shutil
import sys
import tempfile
from pathlib import Path

# Windows runners default stdout to cp1252, which can't encode the emoji in
# labels like "[🚀 PROD]" — printing them crashed the step after the upload.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

from pyrogram import Client

APP_NAME = os.environ.get("APP_NAME", "salla")
REQUIRED_ENV = ("API_ID", "API_HASH", "BOT_TOKEN", "CHAT_ID", "ARTIFACT_PATH", "ARTIFACT_LABEL")


def _require_env() -> dict:
    missing = [name for name in REQUIRED_ENV if not os.environ.get(name)]
    if missing:
        print(f"ERROR: missing required env vars: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)
    return {name: os.environ[name] for name in REQUIRED_ENV}


def _build_caption(label: str, branch: str, short_sha: str, commit_message: str, size_mb: float) -> str:
    commit_message = (commit_message or "").strip()
    if len(commit_message) > 200:
        commit_message = commit_message[:199].rstrip() + "…"

    lines = [
        f"📦 {APP_NAME} — {label}",
        f"Branch: {branch or 'unknown'}",
        f"Commit: {short_sha or 'unknown'}",
        f"Size: {size_mb:.2f} MB",
    ]
    if commit_message:
        lines.append("")
        lines.append(commit_message)
    return "\n".join(lines)


async def _send(file_path: Path, caption: str, creds: dict) -> None:
    app = Client(
        "ci_uploader",
        api_id=int(creds["API_ID"]),
        api_hash=creds["API_HASH"],
        bot_token=creds["BOT_TOKEN"],
        in_memory=True,
    )

    chat_id = int(creds["CHAT_ID"])
    topic_id = os.environ.get("TOPIC_ID", "").strip()
    thread_id = int(topic_id) if topic_id else None

    async with app:
        try:
            chat = await app.get_chat(chat_id)
            print(f"Resolved chat: id={chat.id} type={chat.type} title={getattr(chat, 'title', None)!r}")
        except Exception as exc:
            print(
                f"ERROR: could not resolve chat_id {chat_id!r}: {exc!r}\n"
                "Check that (a) the ID is the full -100… form, "
                "(b) the bot is a member/admin of the chat.",
                file=sys.stderr,
            )
            raise

        kwargs = {
            "chat_id": chat_id,
            "document": str(file_path),
            "caption": caption,
            "force_document": True,
        }
        if thread_id is not None:
            kwargs["message_thread_id"] = thread_id

        await app.send_document(**kwargs)


async def main() -> None:
    creds = _require_env()

    source = Path(creds["ARTIFACT_PATH"])
    if not source.is_file():
        print(f"ERROR: artifact not found at {source}", file=sys.stderr)
        sys.exit(1)

    commit_sha = os.environ.get("COMMIT_SHA", "")
    short_sha = commit_sha[:7] if commit_sha else "unknown"
    branch = os.environ.get("BRANCH_NAME", "")
    commit_message = os.environ.get("COMMIT_MESSAGE", "")
    label = creds["ARTIFACT_LABEL"]
    env_tag = {"testing": "🧪 TEST", "production": "🚀 PROD"}.get(os.environ.get("API_ENV", "").strip())
    if env_tag:
        label = f"{label} [{env_tag}]"

    size_mb = source.stat().st_size / (1024 * 1024)
    caption = _build_caption(label, branch, short_sha, commit_message, size_mb)

    upload_name = os.environ.get("ARTIFACT_FILENAME") or source.name

    with tempfile.TemporaryDirectory() as tmpdir:
        staged = Path(tmpdir) / upload_name
        shutil.copy2(source, staged)

        print(f"Uploading {staged.name} ({size_mb:.2f} MB) to chat {creds['CHAT_ID']}…")
        try:
            await _send(staged, caption, creds)
        except Exception as exc:  # noqa: BLE001 - surface any failure to the workflow
            print(f"ERROR: failed to send {label} to Telegram: {exc!r}", file=sys.stderr)
            sys.exit(1)

    print(f"{label} delivered to Telegram.")


if __name__ == "__main__":
    asyncio.run(main())
