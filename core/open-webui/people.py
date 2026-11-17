#!/usr/bin/env python3
"""Create Open WebUI accounts from a people file ("Name, e-mail[, admin]" per line).

Temporary passwords go to OUTPUT (mode 600), never to stdout. Existing accounts are skipped.
Prints the number created, then every e-mail in the file.

Usage: python3 people.py PEOPLE OUTPUT   (ALICE_TEST_URL, ALICE_TEST_ADMIN_EMAIL, ALICE_TEST_ADMIN_PASSWORD)"""
import csv
import os
import secrets
import sys
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tests"))
from owui import ApiError, Client, settings  # noqa: E402


def people(path):
    for row in csv.reader(open(path, encoding="utf-8")):
        row = [cell.strip() for cell in row]
        if len(row) >= 2 and "@" in row[1] and not row[0].startswith("#"):
            yield row[0], row[1].lower(), (row[2].lower() if len(row) > 2 and row[2].lower() == "admin" else "user")


def main():
    source, output = sys.argv[1], sys.argv[2]
    admin = Client.signin(*settings())
    created, failed, everyone = 0, [], []
    for name, email, role in people(source):
        try:
            found = admin.call(f"/api/v1/users/?query={urllib.parse.quote(email)}")["users"]
            if not any(u["email"].lower() == email for u in found):
                password = secrets.token_urlsafe(12)
                admin.call("/api/v1/auths/add", {"name": name, "email": email, "password": password, "role": role})
                # Written at once: a later failure must not lose a password already given.
                fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
                with os.fdopen(fd, "a", encoding="utf-8", newline="") as f:
                    csv.writer(f).writerow((name, email, role, password))
                created += 1
            everyone.append(email)
        except ApiError as e:
            failed.append(f"{email} ({e})")
    print(f"created {created}" + (f", failed: {'; '.join(failed)}" if failed else ""))
    print(" ".join(everyone))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
