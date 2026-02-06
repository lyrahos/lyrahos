#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Lyrah OS session selection module for Calamares.
# Presents radio buttons for the user to pick a default session
# (Luna Mode, Desktop Mode, or no default). The choice is stored in
# Calamares GlobalStorage so the shellprocess module can pass it to
# configure-session.sh during the exec phase.

import libcalamares

try:
    from PythonQt.QtWidgets import (
        QWidget, QVBoxLayout, QLabel, QRadioButton, QButtonGroup,
    )
except ImportError:
    from PythonQt.QtGui import (
        QWidget, QVBoxLayout, QLabel, QRadioButton, QButtonGroup,
    )

_DEFAULT_SESSIONS = [
    {
        "name": "Luna Mode (Gaming)",
        "description": "Console-like gaming experience. Recommended for gaming PCs.",
        "session": "luna-mode",
    },
    {
        "name": "Desktop Mode (KDE Plasma)",
        "description": "Full desktop environment. Recommended for general use.",
        "session": "plasma",
    },
    {
        "name": "No Default (Show Login Screen)",
        "description": "Choose your session at each login.",
        "session": "none",
    },
]

_selected_session = "luna-mode"


def pretty_name():
    return "Default Session"


def _on_session_changed(session_id):
    global _selected_session
    _selected_session = session_id
    libcalamares.globalstorage.insert("lyrah_session", session_id)


def widget():
    global _selected_session

    # Try reading session list from module configuration; fall back to defaults.
    cfg = {}
    if hasattr(libcalamares, "job") and libcalamares.job is not None:
        cfg = libcalamares.job.configuration or {}
    sessions = cfg.get("sessions", _DEFAULT_SESSIONS)

    page = QWidget()
    layout = QVBoxLayout(page)

    heading = QLabel(
        "<h2>Choose Your Default Session</h2>"
        "<p>Select which session starts automatically when you log in. "
        "You can change this later with <code>lyrah-switch-mode</code>.</p>"
    )
    heading.setWordWrap(True)
    layout.addWidget(heading)

    group = QButtonGroup(page)

    for i, session in enumerate(sessions):
        radio = QRadioButton(page)
        radio.setText(session["name"])
        radio.setToolTip(session.get("description", ""))

        # First option selected by default
        if i == 0:
            radio.setChecked(True)
            _selected_session = session["session"]

        sid = session["session"]
        radio.toggled.connect(
            lambda checked, s=sid: _on_session_changed(s) if checked else None
        )

        group.addButton(radio, i)
        layout.addWidget(radio)

        desc = QLabel("<small>" + session.get("description", "") + "</small>")
        desc.setWordWrap(True)
        desc.setContentsMargins(24, 0, 0, 8)
        layout.addWidget(desc)

    layout.addStretch(1)

    # Store the default selection in GlobalStorage immediately so it is
    # available even if the user clicks through without changing anything.
    libcalamares.globalstorage.insert("lyrah_session", _selected_session)

    return page


def run():
    """Safety net: ensure GlobalStorage has a value during exec phase."""
    if not libcalamares.globalstorage.contains("lyrah_session"):
        libcalamares.globalstorage.insert("lyrah_session", _selected_session)
    return None
